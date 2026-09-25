#!/usr/bin/env perl
# Builds and installs the fitting engine - minuit, the core (this repo) and its
# extensions - into an install root, safely. Shared by onefite-go's
# `doctor --install` and OneFit-Engine's INSTALL, which only fetch the sources
# (minuit and onefite-c-code) and then call:
#
#   perl tools/engine.pl install --c-root C --root ROOT [--minuit-dir DIR]
#        [--minuit-max-params N] [--keep-minuit]
#        [--os LINUX|MacOSX] [--arch x86_64|aarch64] [--perlcore DIR] [--bindir DIR]
#        [--extension NAME[=URL[@REF]]]... [--no-default-extensions]
#        [--transport https|http|ssh] [--ref REF] [--no-fetch]
#        [--sources DIR] [--if-changed]
#   perl tools/engine.pl migrate  --c-root C          (only the layout repair)
#   perl tools/engine.pl linktest --c-root C --root ROOT
#   perl tools/engine.pl rollback --c-root C --root ROOT
#
# install, in order:
#  1. takes ROOT/.engine.lock, so two installs never run at once;
#  2. repairs the pre-2026 extensions layout (an extensions clone occupying
#     C/extensions itself) - see migrate below;
#  3. fetches extensions. With no extension options it updates the ones
#     already installed (ROOT/etc/engine.json, else onefite-go's
#     etc/config.json, else the checkouts in C/extensions) rather than the
#     registry defaults, so an upgrade never swaps e.g. florence-nag for
#     florence; one of those that cannot be fetched (offline, a private
#     repository root cannot reach) keeps its current checkout. Only a fresh
#     install gets the registry defaults;
#  4. backs up the installed engine files to ROOT/.engine-previous.new;
#  5. builds minuit (skipped with --keep-minuit when ROOT/lib/libminuit.a
#     exists), the core (make install) and the extensions;
#  6. links a test program with every object of every installed extension
#     forced in, using the per-fit makefile's own link line
#     (ROOT/etc/OFE/default/makefile), so whatever an extension calls resolves;
#  7. on success writes ROOT/etc/engine.json and keeps the backup as
#     ROOT/.engine-previous (one step for `rollback`); on any failure puts
#     the backed-up engine back exactly and exits 1 - the previous engine
#     keeps working.
#
# --sources DIR (a package's bundled sources: DIR/sources.json and git
# bundles): extensions come only from DIR, never from the network - a
# bundled one is updated from its bundle (only forward: a checkout that is
# already newer is kept), any other installed one (your own, florence-nag)
# keeps its checkout and is rebuilt against the new core.
# --if-changed: when the core, minuit and every extension are at the commits
# ROOT/etc/engine.json recorded, nothing is rebuilt.
# --keep-minuit keeps an installed lib/libminuit.a only while minuit's
# checkout is still at the recorded commit.
#
# "Engine files" are only what this repo installs into ROOT: lib/*.a *.dat
# *.h, include/, share/extensions/, etc/engine.mk, etc/extensions.mk,
# etc/engine.json, plus C/META-CATALOG.json. Nothing else in ROOT (e.g.
# OneFit-Engine's own lib/*.rakumod or bin/onefite) is ever touched. The small
# utilities installed to BINDIR are rebuilt but not backed up.
#
# Core Perl only (plus git, make and the compilers the build needs).
use strict;
use warnings;
use Cwd qw(abs_path);
use Fcntl qw(:flock);
use File::Basename qw(dirname basename);
use File::Path qw(make_path remove_tree);
use File::Spec;
use File::Temp qw(tempdir);
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP ();
use POSIX qw(strftime);

my $HERE = dirname(abs_path($0));
my $json = JSON::PP->new->utf8->canonical->pretty;
my $OLD_FLORENCE_REPO = qr{fitteia/onefite-external-extensions(?:\.git)?$};
my $FLORENCE_URL = 'https://github.com/fitteia/onefite-ext-florence.git';

sub say_  { print STDERR "===> $_[0]\n" }
sub warn_ { print STDERR "===> WARNING: $_[0]\n" }
sub fail  { print STDERR "error: $_[0]\n"; exit 2 }

sub slurp {
    my ($p) = @_;
    open my $fh, '<', $p or return undef;
    local $/;
    return scalar <$fh>;
}

sub spew {
    my ($p, $text) = @_;
    make_path(dirname($p));
    open my $fh, '>', $p or die "cannot write $p: $!\n";
    print {$fh} $text;
    close $fh or die "cannot write $p: $!\n";
}

sub run_ok { my $rc = system(@_); return $rc == 0 }

sub git_out {
    my ($dir, @args) = @_;
    open my $fh, '-|', 'git', '-C', $dir, '-c', 'safe.directory=*', @args or return undef;
    my $out = do { local $/; <$fh> };
    close $fh or return undef;
    $out =~ s/\s+\z// if defined $out;
    return $out;
}

sub git_ok { my ($dir, @args) = @_; return run_ok('git', '-C', $dir, '-c', 'safe.directory=*', @args) }

# ---- 2. the pre-2026 extensions layout ---------------------------------
#
# Doctor/INSTALL used to clone the extensions repository straight into
# C/extensions. Once this repo started tracking its own extensions/ files,
# pulling it wrote them into that clone, and moving the clone aside later took
# them along. migrate: moves such a clone to extensions/florence (it is the
# repository florence now lives in; its old URL is repointed there), puts
# back this repo's own extensions/ files that are missing, and removes from
# extensions/florence the top-level entries that are this repo's files, not
# the clone's. Idempotent; never deletes a checkout.
sub migrate {
    my ($c) = @_;
    my $ext = "$c/extensions";
    my $stash = "$c/extensions.migrating";
    if (-d "$ext/.git" && !-e $stash) {
        rename $ext, $stash or die "cannot move $ext aside: $!\n";
        say_('moving the old extensions clone to extensions/florence');
    }
    if (-d $stash) {
        git_ok($c, 'checkout', '--', 'extensions') if -d "$c/.git";
        make_path($ext);
        my $dst = "$ext/florence";
        if (-e $dst) {
            my $kept = "$c/extensions.legacy-" . time;
            rename $stash, $kept or die "cannot move $stash: $!\n";
            say_("extensions/florence already exists; old clone kept at $kept");
        } else {
            rename $stash, $dst or die "cannot move $stash to $dst: $!\n";
        }
    }
    return unless -d "$c/.git";
    my @deleted = split /\0/, (git_out($c, 'ls-files', '--deleted', '-z', '--', 'extensions') // '');
    if (@deleted) {
        git_ok($c, 'checkout', '--', @deleted) or die "cannot restore @deleted\n";
        say_('restored ' . scalar(@deleted) . ' base file(s) under extensions/ lost by the old layout');
    }
    my $fl = "$ext/florence";
    return unless -d "$fl/.git";
    my %seen;
    for my $p (split /\0/, (git_out($c, 'ls-files', '-z', '--', 'extensions') // '')) {
        (my $rel = $p) =~ s{^extensions/}{};
        my ($top) = split m{/}, $rel;
        next if !$top || $top eq 'florence' || $seen{$top}++;
        next unless -e "$fl/$top" || -l "$fl/$top";
        next if length(git_out($fl, 'ls-files', '--', $top) // '');
        remove_tree("$fl/$top");
        unlink "$fl/$top";
        say_("removed $top from extensions/florence (a base-repo file left there by the old layout)");
    }
    my $url = git_out($fl, 'config', '--get', 'remote.origin.url') // '';
    if ($url =~ $OLD_FLORENCE_REPO) {
        git_ok($fl, 'remote', 'set-url', 'origin', $FLORENCE_URL);
        say_("extensions/florence: origin $url -> $FLORENCE_URL");
    }
}

# ---- 3. which extensions --------------------------------------------------

sub read_json { my $t = slurp($_[0]); return $t ? eval { JSON::PP->new->utf8->decode($t) } : undef }

# The extensions the previous install left, as [name, repo, ref]: the shared
# record, else onefite-go's, else the checkouts themselves.
sub installed_extensions {
    my ($c, $root) = @_;
    for my $f ("$root/etc/engine.json", "$root/etc/config.json") {
        my $doc = read_json($f) or next;
        my @e = grep { $_->{name} && $_->{repo} } @{ $doc->{extensions} // [] };
        return map { [ $_->{name}, $_->{repo}, $_->{ref} || 'main' ] } @e if @e;
    }
    my @found;
    opendir my $dh, "$c/extensions" or return ();
    for my $n (sort grep { !/^\./ && $_ ne 'template' } readdir $dh) {
        my $d = "$c/extensions/$n";
        next unless -f "$d/extension.json" && -d "$d/.git";
        my $url = git_out($d, 'config', '--get', 'remote.origin.url') or next;
        push @found, [ $n, $url, 'main' ];
    }
    closedir $dh;
    return @found;
}

sub fetch_ext {
    my ($c, @args) = @_;
    my $cmd = join ' ', map { quotemeta } 'perl', "$c/tools/extensions.pl", 'fetch', '--c-root', $c, '--json', @args;
    my $out = `$cmd`;
    return undef if $?;
    return eval { JSON::PP->new->utf8->decode($out) } // [];
}

# Returns the fetched/kept extensions as records, or dies.
sub fetch_extensions {
    my ($c, $root, $o) = @_;
    return [] unless -f "$c/tools/extensions.pl";
    my @common = ('--ref', $o->{ref});
    push @common, '--transport', $o->{transport} if $o->{transport};
    my $explicit = @{ $o->{extension} } || $o->{no_default_extensions};
    my @installed = $explicit ? () : installed_extensions($c, $root);
    if (!@installed) {
        my @args = @common;
        push @args, '--no-default-extensions' if $o->{no_default_extensions};
        push @args, map { ('--extension', $_) } @{ $o->{extension} };
        my $got = fetch_ext($c, @args);
        die "could not fetch the requested extensions\n" if !defined $got && @{ $o->{extension} };
        warn_('could not fetch the default extensions - continuing without updating them') unless defined $got;
        return $got // [];
    }
    say_('updating the installed extensions: ' . join(' ', map { $_->[0] } @installed));
    my @recs;
    for my $e (@installed) {
        my ($name, $url, $ref) = @$e;
        my $got = fetch_ext($c, '--no-default-extensions', '--extension', "$name=$url\@$ref", '--ref', $ref,
            $o->{transport} ? ('--transport', $o->{transport}) : ());
        if ($got && @$got) {
            push @recs, @$got;
        } elsif (-d "$c/extensions/$name/.git") {
            warn_("could not fetch extension $name from $url - keeping its current checkout");
            push @recs, { name => $name, repo => $url, ref => $ref,
                          commit => git_out("$c/extensions/$name", 'rev-parse', 'HEAD') // '?' };
        } else {
            die "could not fetch extension $name from $url, and it has no checkout\n";
        }
    }
    return \@recs;
}

# ---- 3b. bundled sources (--sources) ---------------------------------

sub sources_doc {
    my ($dir) = @_;
    my $doc = read_json("$dir/sources.json") or die "no readable $dir/sources.json\n";
    return $doc;
}

# Brings a checkout to a bundle's commit: clones it when missing (origin
# set to the real repository), otherwise moves it forward only - a
# checkout that is already newer, or has diverged, is kept as it is.
sub update_from_bundle {
    my ($dir, $bundle, $repo, $commit, $what) = @_;
    if (!-d "$dir/.git") {
        make_path(dirname($dir));
        run_ok('git', 'clone', '-q', $bundle, $dir) or die "cannot clone $bundle\n";
        git_ok($dir, 'remote', 'set-url', 'origin', $repo) if $repo;
        git_ok($dir, 'checkout', '-q', '--force', $commit) or die "no commit $commit in $bundle\n";
        say_("$what at " . substr($commit, 0, 7) . ' (bundled)');
        return;
    }
    git_ok($dir, 'fetch', '-q', $bundle, 'HEAD') or die "cannot fetch $bundle into $dir\n";
    my $head = git_out($dir, 'rev-parse', 'HEAD') // '';
    if ($head eq $commit) {
        say_("$what already at " . substr($commit, 0, 7));
    } elsif (git_ok($dir, 'merge-base', '--is-ancestor', $head, $commit)) {
        git_ok($dir, 'checkout', '-q', '--force', $commit) or die "cannot check out $commit in $dir\n";
        say_("$what: " . substr($head, 0, 7) . ' -> ' . substr($commit, 0, 7) . ' (bundled)');
    } else {
        say_("$what: keeping " . substr($head, 0, 7) . ' (newer than or diverged from the bundled ' . substr($commit, 0, 7) . ')');
    }
}

sub ext_record {
    my ($c, $name, $ref) = @_;
    my $d = "$c/extensions/$name";
    return { name => $name, repo => git_out($d, 'config', '--get', 'remote.origin.url') // '',
             ref => $ref || 'main', commit => git_out($d, 'rev-parse', 'HEAD') // '?' };
}

# --sources: the extensions to install, from the bundles only.
sub extensions_from_sources {
    my ($c, $root, $o) = @_;
    my $src = sources_doc($o->{sources});
    my %bundled = %{ $src->{extensions} // {} };
    my @installed = installed_extensions($c, $root);
    my @names = @installed ? map { $_->[0] } @installed
              : $o->{no_default_extensions} ? ()
              : sort keys %bundled;
    my %ref = map { $_->[0] => $_->[2] } @installed;
    my @recs;
    for my $n (@names) {
        my $b = $bundled{$n};
        my $d = "$c/extensions/$n";
        my $origin = -d "$d/.git" ? (git_out($d, 'config', '--get', 'remote.origin.url') // '') : '';
        if ($b && (!-d "$d/.git" || same_repo($origin, $b->{repo}))) {
            update_from_bundle($d, "$o->{sources}/$b->{bundle}", $b->{repo}, $b->{commit}, "extension $n");
        } elsif (-d "$d/.git") {
            say_("extension $n: not in this package - keeping its checkout (rebuilt against the new core)");
        } else {
            die "extension $n is recorded as installed but has no checkout and is not in this package\n";
        }
        push @recs, ext_record($c, $n, $ref{$n});
    }
    return \@recs;
}

sub same_repo {
    my ($a, $b) = map { my $u = lc($_ // ''); $u =~ s{\.git$}{}; $u =~ s{^git\@github\.com:}{https://github.com/}; $u } @_;
    return $a eq $b;
}

# --if-changed: true when everything is at the recorded commits.
sub unchanged {
    my ($c, $root, $o, $exts) = @_;
    my $rec = read_json("$root/etc/engine.json") or return 0;
    return 0 unless -f "$root/etc/engine.mk" && -f "$root/lib/libminuit.a";
    return 0 unless ($rec->{core}{commit} // '') eq (git_out($c, 'rev-parse', 'HEAD') // '-');
    my ($ln) = (slurp("$c/libnumber.mk") // '') =~ /^LIBNUMBER\s*=\s*(\S+)/m;
    return 0 unless ($rec->{libnumber} // '') eq ($ln // '-');
    if ($o->{minuit_dir} && -d "$o->{minuit_dir}/.git") {
        return 0 unless ($rec->{minuit}{commit} // '') eq (git_out($o->{minuit_dir}, 'rev-parse', 'HEAD') // '-');
    }
    return 0 if $o->{minuit_max_params} && $o->{minuit_max_params} != ($rec->{minuit}{max_params} // 0);
    my %want = map { $_->{name} => $_->{commit} } @{ $rec->{extensions} // [] };
    my %have = map { $_->{name} => $_->{commit} } @$exts;
    return 0 unless join(',', map { "$_=$want{$_}" } sort keys %want) eq join(',', map { "$_=$have{$_}" } sort keys %have);
    return 1;
}

# ---- 4/7. backup and restore -----------------------------------------

sub engine_items {
    my ($c, $root) = @_;
    my @items = map { "include/$_" } grep { 1 } list_dir("$root/include");
    push @items, 'share/extensions' if -e "$root/share/extensions";
    push @items, map { "etc/$_" } grep { -e "$root/etc/$_" } qw(engine.mk extensions.mk engine.json);
    push @items, map { "lib/$_" } grep { /\.(?:a|dat|h)$/ } list_dir("$root/lib");
    return @items;
}

sub list_dir {
    my ($d) = @_;
    opendir my $dh, $d or return ();
    my @n = sort grep { $_ ne '.' && $_ ne '..' } readdir $dh;
    closedir $dh;
    return @n;
}

sub copy_item {
    my ($from, $to) = @_;
    make_path(dirname($to));
    run_ok('cp', '-pPR', $from, $to) or die "cannot copy $from to $to\n";
}

sub backup {
    my ($c, $root, $dst) = @_;
    remove_tree($dst);
    make_path($dst);
    copy_item("$root/$_", "$dst/root/$_") for engine_items($c, $root);
    copy_item("$c/META-CATALOG.json", "$dst/c-root/META-CATALOG.json") if -e "$c/META-CATALOG.json";
    spew("$dst/items", join('', map { "$_\n" } engine_items($c, $root)));
}

sub restore {
    my ($c, $root, $src) = @_;
    for my $i (engine_items($c, $root)) {
        remove_tree("$root/$i");
        unlink "$root/$i";
    }
    unlink "$c/META-CATALOG.json";
    for my $i (list_dir("$src/root")) {
        for my $j (-d "$src/root/$i" && !-l "$src/root/$i" ? map { "$i/$_" } list_dir("$src/root/$i") : ($i)) {
            copy_item("$src/root/$j", "$root/$j");
        }
    }
    copy_item("$src/c-root/META-CATALOG.json", "$c/META-CATALOG.json") if -e "$src/c-root/META-CATALOG.json";
}

# ---- 5. build -----------------------------------------------------------

sub patch_minuit_limit {
    my ($m, $n) = @_;
    my $inc = "$m/minuit/d506cm.inc";
    my $t = slurp($inc) // die "cannot read $inc\n";
    my $line = sprintf '      PARAMETER (MNE=%d , MNI=%d)', 2 * $n, $n;
    $t =~ s/^.*PARAMETER\s*\(\s*MNE\s*=.*$/$line/mi or die "no PARAMETER (MNE=...) line in $inc\n";
    spew($inc, $t);
}

sub build_minuit {
    my ($m, $root, $n) = @_;
    die "--minuit-dir is needed to build minuit (none at $root/lib/libminuit.a)\n" unless $m && -d $m;
    git_ok($m, 'checkout', '--', 'minuit/d506cm.inc') if -d "$m/.git";
    patch_minuit_limit($m, $n);
    say_("building minuit with a maximum of $n parameters");
    run_ok('make', '-C', $m, 'clean');
    my $ok = run_ok('make', '-C', $m, 'lib');
    git_ok($m, 'checkout', '--', 'minuit/d506cm.inc') if -d "$m/.git";
    die "building minuit failed\n" unless $ok && -f "$m/libminuit.a";
    make_path("$root/lib");
    copy_item("$m/libminuit.a", "$root/lib/libminuit.a");
}

sub build_core {
    my ($c, $root, $o) = @_;
    my @vars = ("OS=$o->{os}", "ARCH=$o->{arch}", "ROOT=$root", "PERLCORE=$o->{perlcore}", "BINDIR=$o->{bindir}");
    say_("building the core (onefite-c-code) into $root");
    run_ok('make', '-C', $c, @vars, 'clean');
    run_ok('make', '-C', $c, @vars, 'install') or die "building the core (onefite-c-code) failed\n";
}

sub build_extensions {
    my ($c, $root) = @_;
    return 1 unless -f "$c/tools/extensions.pl";
    return run_ok('perl', "$c/tools/extensions.pl", 'install', '--c-root', $c, '--root', $root);
}

# ---- 6. link test ---------------------------------------------------------

# Links a program with every object of every installed extension library
# forced in (--whole-archive; -force_load on macOS), using the per-fit
# makefile's own CC and LIB - the exact line every fit links with. So any
# function an extension calls must resolve against the core, minuit and the
# other libraries now, not at the first fit that happens to use it; a missing
# library shows up too.
sub linktest {
    my ($c, $root) = @_;
    my $mk = "$root/etc/OFE/default/makefile";
    unless (-f $mk) {
        warn_("no $mk - link test skipped");
        return 1;
    }
    my $t = tempdir(CLEANUP => 1);
    spew("$t/vars.mk", "include $mk\nengine-linktest-vars:\n\t\@echo \"CC=\$(CC)\"\n\t\@echo \"LIB=\$(LIB)\"\n");
    my $vars = `make -s -f $t/vars.mk engine-linktest-vars ROOT=$root PREFIX= 2>&1`;
    my ($cc)  = $vars =~ /^CC=(.*)$/m;
    my ($lib) = $vars =~ /^LIB=(.*)$/m;
    unless (defined $cc && defined $lib) {
        print STDERR "error: cannot read CC/LIB from $mk:\n$vars";
        return 0;
    }
    my @ext = $lib =~ /-lonefit-ext-([\w.+-]+)/g;
    for my $n (@ext) {
        my $a = "$root/lib/libonefit-ext-$n.a";
        my $forced = $^O eq 'darwin' ? "-Wl,-force_load,$a"
                                     : "-Wl,--whole-archive $a -Wl,--no-whole-archive";
        $lib =~ s/(^|\s)-lonefit-ext-\Q$n\E(?=\s|$)/$1$forced/;
    }
    spew("$t/t.c", "int main(void) { return 0; }\n");
    my $out = `cd $t && $cc t.c $lib -o t 2>&1`;
    if ($?) {
        print STDERR "error: the link test failed ($cc t.c $lib):\n$out";
        return 0;
    }
    say_('link test passed (' . scalar(@ext) . ' extension librar' . (@ext == 1 ? 'y' : 'ies') . ', every object linked)');
    return 1;
}

# ---- 7. record ----------------------------------------------------------

# Every extension actually installed - each checkout with an extension.json,
# not just the ones this run fetched - with the ref it follows (this run's,
# else the previous record's, else main).
sub installed_records {
    my ($c, $root, $exts) = @_;
    my %ref = map { $_->[0] => $_->[2] } installed_extensions($c, $root);
    $ref{ $_->{name} } = $_->{ref} for grep { $_->{ref} } @$exts;
    my @recs;
    for my $n (list_dir("$c/extensions")) {
        next if $n eq 'template' || !-f "$c/extensions/$n/extension.json" || !-d "$c/extensions/$n/.git";
        push @recs, ext_record($c, $n, $ref{$n});
    }
    return \@recs;
}

sub write_record {
    my ($c, $root, $o, $exts, $minuit_limit) = @_;
    my ($libnumber) = (slurp("$root/etc/engine.mk") // '') =~ /LIBNUMBER\s*:?=\s*(\S+)/;
    my %rec = (
        schema       => 1,
        installed_at => strftime('%Y-%m-%dT%H:%M:%SZ', gmtime),
        libnumber    => $libnumber,
        core         => { commit => git_out($c, 'rev-parse', 'HEAD'),
                          repo   => git_out($c, 'config', '--get', 'remote.origin.url') },
        minuit       => { max_params => $minuit_limit },
        extensions   => [ map { { name => $_->{name}, repo => $_->{repo}, ref => $_->{ref}, commit => $_->{commit} } } @$exts ],
    );
    if ($o->{minuit_dir} && -d "$o->{minuit_dir}/.git") {
        $rec{minuit}{commit} = git_out($o->{minuit_dir}, 'rev-parse', 'HEAD');
        $rec{minuit}{repo}   = git_out($o->{minuit_dir}, 'config', '--get', 'remote.origin.url');
    }
    spew("$root/etc/engine.json", $json->encode(\%rec));
}

# minuit's checkout is no longer at the commit the installed library was
# built from (unknown counts as not moved).
sub minuit_moved {
    my ($root, $o) = @_;
    return 0 unless $o->{minuit_dir} && -d "$o->{minuit_dir}/.git";
    my $rec = read_json("$root/etc/engine.json") or return 0;
    my $was = $rec->{minuit}{commit} or return 0;
    my $now = git_out($o->{minuit_dir}, 'rev-parse', 'HEAD') // return 0;
    return 0 if $was eq $now;
    say_('minuit changed (' . substr($was, 0, 7) . ' -> ' . substr($now, 0, 7) . ') - rebuilding it despite --keep-minuit');
    return 1;
}

sub minuit_limit {
    my ($root, $o) = @_;
    return $o->{minuit_max_params} if $o->{minuit_max_params};
    for my $f ("$root/etc/engine.json", "$root/etc/config.json") {
        my $doc = read_json($f) or next;
        my $n = ref $doc->{minuit} eq 'HASH' ? $doc->{minuit}{max_params} : $doc->{minuit_max_params};
        return $n if $n;
    }
    return 1000;
}

# ---- commands -----------------------------------------------------------

sub default_os   { return $^O eq 'darwin' ? 'MacOSX' : 'LINUX' }
sub default_arch { my $m = `uname -m`; chomp $m; return $m eq 'arm64' ? 'aarch64' : $m }

sub opts {
    my @args = @_;
    my %o = (extension => [], ref => 'main', os => default_os(), arch => default_arch(),
             perlcore => '/nonexistent');
    GetOptionsFromArray(\@args,
        'c-root=s' => \$o{c_root}, 'root=s' => \$o{root}, 'minuit-dir=s' => \$o{minuit_dir},
        'minuit-max-params=i' => \$o{minuit_max_params}, 'keep-minuit' => \$o{keep_minuit},
        'os=s' => \$o{os}, 'arch=s' => \$o{arch}, 'perlcore=s' => \$o{perlcore}, 'bindir=s' => \$o{bindir},
        'extension=s@' => $o{extension}, 'no-default-extensions' => \$o{no_default_extensions},
        'transport=s' => \$o{transport}, 'ref=s' => \$o{ref}, 'no-fetch' => \$o{no_fetch},
        'sources=s' => \$o{sources}, 'if-changed' => \$o{if_changed},
    ) or exit 2;
    fail('--c-root is required') unless $o{c_root};
    $o{c_root} = abs_path($o{c_root}) // fail("no such directory: $o{c_root}");
    if (defined $o{root}) {
        make_path($o{root});
        $o{root} = abs_path($o{root});
    }
    $o{minuit_dir} = abs_path($o{minuit_dir}) if $o{minuit_dir} && -d $o{minuit_dir};
    $o{sources} = abs_path($o{sources}) // fail("no such directory: $o{sources}") if $o{sources};
    $o{bindir} //= "$o{root}/bin" if $o{root};
    return \%o;
}

sub lock_root {
    my ($root) = @_;
    open my $lk, '>', "$root/.engine.lock" or die "cannot create $root/.engine.lock: $!\n";
    unless (flock $lk, LOCK_EX | LOCK_NB) {
        say_("another engine install is running in $root - waiting for it to finish");
        flock $lk, LOCK_EX or die "cannot lock $root/.engine.lock: $!\n";
    }
    return $lk;
}

sub cmd_install {
    my $o = opts(@_);
    my ($c, $root) = @$o{qw(c_root root)};
    fail('--root is required') unless $root;
    my $lock = lock_root($root);
    migrate($c);
    my %had = map { $_ => 1 } list_dir("$c/extensions");
    my $exts = $o->{sources}  ? extensions_from_sources($c, $root, $o)
             : $o->{no_fetch} ? []
             :                  fetch_extensions($c, $root, $o);
    if ($o->{if_changed} && unchanged($c, $root, $o, $exts)) {
        say_("the engine in $root is up to date (core, minuit and extensions at the recorded commits) - nothing rebuilt");
        return 0;
    }
    my $fresh = !-f "$root/etc/engine.mk" && !-f "$root/lib/libminuit.a";
    my $prev = "$root/.engine-previous";
    backup($c, $root, "$prev.new");
    my $limit = minuit_limit($root, $o);
    my $ok = eval {
        if ($o->{keep_minuit} && -f "$root/lib/libminuit.a" && !$o->{minuit_max_params} && !minuit_moved($root, $o)) {
            say_("keeping the installed $root/lib/libminuit.a (--keep-minuit)");
        } else {
            build_minuit($o->{minuit_dir}, $root, $limit);
        }
        build_core($c, $root, $o);
        unless (build_extensions($c, $root)) {
            die "building the extensions failed\n" if @$exts || !$fresh;
            warn_('the default extensions could not be built - continuing without them');
        }
        linktest($c, $root) or die "the link test failed\n";
        1;
    };
    unless ($ok) {
        my $why = $@ || "unknown error\n";
        print STDERR "error: $why";
        if ($fresh) {
            say_('fresh install failed - nothing to restore');
        } else {
            restore($c, $root, "$prev.new");
            say_("restored the previous engine - it keeps working exactly as before this install");
        }
        remove_tree("$prev.new");
        # A checkout this run cloned would otherwise be built - and fail - by
        # every later install; one that existed before is never touched.
        for my $n (grep { !$had{$_} } list_dir("$c/extensions")) {
            remove_tree("$c/extensions/$n");
            say_("removed extensions/$n, cloned by this failed install");
        }
        exit 1;
    }
    if (-f "$root/lib/libonefit-external-models.a"
        && (slurp("$root/etc/extensions.mk") // '') !~ /external-models/) {
        unlink "$root/lib/libonefit-external-models.a";
        say_('removed lib/libonefit-external-models.a (the old extensions library, no longer linked)');
    }
    write_record($c, $root, $o, installed_records($c, $root, $exts), $limit);
    remove_tree($prev);
    rename "$prev.new", $prev;
    say_("engine installed into $root (previous one kept in $prev for `engine.pl rollback`)");
    return 0;
}

sub cmd_rollback {
    my $o = opts(@_);
    my ($c, $root) = @$o{qw(c_root root)};
    fail('--root is required') unless $root;
    my $prev = "$root/.engine-previous";
    fail("no previous engine to roll back to ($prev)") unless -d "$prev/root";
    my $lock = lock_root($root);
    restore($c, $root, $prev);
    remove_tree($prev);
    say_("rolled back to the previous engine in $root");
    return 0;
}

sub cmd_migrate  { my $o = opts(@_); migrate($o->{c_root}); return 0 }
sub cmd_linktest { my $o = opts(@_); fail('--root is required') unless $o->{root}; return linktest($o->{c_root}, $o->{root}) ? 0 : 1 }

my %cmds = (install => \&cmd_install, migrate => \&cmd_migrate, linktest => \&cmd_linktest, rollback => \&cmd_rollback);
my $cmd = shift // '';
my $run = $cmds{$cmd} or do {
    print STDERR "usage: $0 install|migrate|linktest|rollback --c-root DIR [--root DIR] ...\n";
    exit 2;
};
my $rc = eval { $run->(@ARGV) };
unless (defined $rc) {
    print STDERR "error: $@";
    exit 1;
}
exit $rc;
