#!/usr/bin/env perl
# Tests for tools/engine.pl. Run: perl tools/test_engine.t   (make engine-selftest)
# The full-install part builds this repo's HEAD (needs make, cc and gfortran);
# it is skipped when they are missing.
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $HERE   = dirname(abs_path($0));
my $C_ROOT = abs_path("$HERE/..");
my $DRIVER = "$HERE/engine.pl";
my $CAN_BUILD = !system('command -v make >/dev/null 2>&1 && command -v cc >/dev/null 2>&1 && command -v gfortran >/dev/null 2>&1');

sub slurp { open my $f, '<:raw', $_[0] or die "$_[0]: $!"; local $/; <$f> }
sub spew  { make_path(dirname($_[0])); open my $f, '>:raw', $_[0] or die "$_[0]: $!"; print {$f} $_[1]; close $f }
sub sh    { system(@_) == 0 or die "failed: @_" }
sub git   { my ($d, @a) = @_; sh('git', '-C', $d, '-c', 'user.name=t', '-c', 'user.email=t@t', '-c', 'init.defaultBranch=main', @a) }
sub gitq  { my ($d, @a) = @_; my $o = qx{git -C \Q$d\E @{[ map { quotemeta } @a ]} 2>/dev/null}; chomp $o; $o }

sub run {
    my (@args) = @_;
    my $out = qx{perl $DRIVER @{[ map { quotemeta } @args ]} 2>&1};
    return ($? >> 8, $out);
}

# md5-free fingerprint of a tree: path, size and content, symlinks by target
sub state {
    my ($root, @dirs) = @_;
    my @lines;
    for my $d (@dirs) {
        next unless -e "$root/$d";
        for my $f (split /\n/, qx{cd \Q$root\E && find \Q$d\E \\( -type f -o -type l \\) | sort}) {
            push @lines, -l "$root/$f" ? "$f -> " . readlink("$root/$f") : "$f " . unpack('%32C*', slurp("$root/$f"));
        }
    }
    return join "\n", @lines;
}

# ---- migrate: the pre-2026 layout -------------------------------------
{
    my $c = tempdir(CLEANUP => 1);
    git($c, 'init', '-q');
    spew("$c/extensions/README.md", "base readme");
    spew("$c/extensions/extension.mk", "rules");
    spew("$c/extensions/template/example.c", "tmpl");
    git($c, 'add', '.');
    git($c, 'commit', '-qm', 'base');
    my $ext = "$c/extensions";
    git($c, 'init', '-q', 'extensions');
    spew("$ext/Makefile", "florence make");
    spew("$ext/README.md", "florence readme");
    git($ext, 'add', 'Makefile', 'README.md');
    git($ext, 'commit', '-qm', 'florence');
    git($ext, 'remote', 'add', 'origin', 'git@github.com:fitteia/onefite-external-extensions.git');
    spew("$ext/build/lib.a", "built");

    my ($rc, $out) = run('migrate', '--c-root', $c);
    is($rc, 0, 'migrate');
    my $fl = "$ext/florence";
    is(slurp("$fl/Makefile"), 'florence make', 'the old clone is now extensions/florence');
    is(slurp("$fl/build/lib.a"), 'built', '...with its untracked files');
    ok(!-e "$fl/extension.mk" && !-e "$fl/template", "...without the base repo's files");
    is(slurp("$ext/extension.mk"), 'rules', "the base repo's own extensions/ files are back");
    is(slurp("$ext/template/example.c"), 'tmpl', '...all of them');
    is(gitq($c, 'status', '--porcelain', '--untracked-files=no', '--', 'extensions'), '', '...so the base repo is clean');
    is(gitq($fl, 'remote', 'get-url', 'origin'), 'https://github.com/fitteia/onefite-ext-florence.git',
        "the old repository's URL points at onefite-ext-florence");
    like($out, qr/moving the old extensions clone/, 'reported');

    ($rc, $out) = run('migrate', '--c-root', $c);
    is($rc, 0, 'migrate again');
    unlike($out, qr/moving|removed|restored|origin/, '...changes nothing');
}

# ---- rollback: only engine files, exactly ------------------------------
{
    my $c = tempdir(CLEANUP => 1);
    my $root = tempdir(CLEANUP => 1);
    spew("$root/lib/OneFit.rakumod", 'runtime file');
    spew("$root/bin/onefite", 'runtime binary');
    spew("$root/lib/libonefit-5.0.0.a", 'new lib');
    spew("$root/lib/libnew-only.a", 'added by the new install');
    spew("$root/include/userlib.h", 'new header');
    spew("$root/etc/engine.mk", "LIBNUMBER := 5.0.0\n");
    spew("$c/META-CATALOG.json", 'new catalog');
    my $prev = "$root/.engine-previous";
    spew("$prev/root/lib/libonefit-5.0.0.a", 'old lib');
    spew("$prev/root/include/userlib.h", 'old header');
    spew("$prev/root/etc/engine.mk", "LIBNUMBER := 4.9.0\n");
    spew("$prev/c-root/META-CATALOG.json", 'old catalog');
    symlink 'libonefit-5.0.0.a', "$prev/root/lib/libonefit-4.0.4.a";

    my ($rc) = run('rollback', '--c-root', $c, '--root', $root);
    is($rc, 0, 'rollback');
    is(slurp("$root/lib/libonefit-5.0.0.a"), 'old lib', 'the previous library is back');
    is(readlink("$root/lib/libonefit-4.0.4.a"), 'libonefit-5.0.0.a', '...symlinks as symlinks');
    ok(!-e "$root/lib/libnew-only.a", 'a library only the new install had is gone');
    is(slurp("$root/include/userlib.h"), 'old header', 'headers are back');
    is(slurp("$c/META-CATALOG.json"), 'old catalog', 'the model catalog is back');
    is(slurp("$root/lib/OneFit.rakumod"), 'runtime file', "the runtime's own files are untouched");
    is(slurp("$root/bin/onefite"), 'runtime binary', '...including bin/');
    ok(!-e $prev, 'the rollback point is used up');
    is((run('rollback', '--c-root', $c, '--root', $root))[0], 2, 'a second rollback: nothing to roll back to');
}

# ---- a real install: fresh, upgrade, failure ---------------------------
SKIP: {
    skip 'needs make, cc and gfortran', 1 unless $CAN_BUILD;
    my $w = tempdir(CLEANUP => 1);
    my $c = "$w/c-code";
    sh('git', 'clone', '-q', $C_ROOT, $c);
    sh('cp', "$DRIVER", "$c/tools/engine.pl");   # the version under test
    my $root = "$w/root";
    # a stand-in minuit (nothing here calls it) and a minimal per-fit makefile
    make_path("$root/lib");
    spew("$w/m.c", "void mn_stub(void) {}\n");
    sh("cd $w && cc -c m.c && ar rcs $root/lib/libminuit.a m.o");
    spew("$root/etc/OFE/default/makefile", <<'MK');
DESTDIR=$(ROOT)$(PREFIX)
LIBNUMBER=4.0.4
-include $(DESTDIR)/etc/engine.mk
-include $(DESTDIR)/etc/extensions.mk
CC=cc
LIB= -L$(DESTDIR)/lib $(EXTERNAL_MODEL_LIBS) -luserlib -lonefit-$(LIBNUMBER) -lonefit-modelos-$(LIBNUMBER) -lonefit-util-$(LIBNUMBER) -lminuit -lgfortran -lm
MK
    my $mkext = sub {
        my ($name, $extra) = @_;
        my $d = "$w/$name";
        sh('cp', '-R', "$C_ROOT/extensions/template", $d);
        my $m = slurp("$d/extension.json");
        $m =~ s/"name": "example"/"name": "$name"/;
        spew("$d/extension.json", $m);
        # its own function name, then a call to a function nothing defines -
        # as if it relied on a core model that is not there
        if ($extra) {
            for my $f (qw(extension.json META-C-model.json example.c example.h)) {
                (my $t = slurp("$d/$f")) =~ s/ExampleGain/${name}Gain/g;
                spew("$d/$f", $t);
            }
        }
        spew("$d/example.c", slurp("$d/example.c")
            . "double core_model_that_is_gone(double);\ndouble uses_it(double x) { return core_model_that_is_gone(x); }\n")
            if $extra;
        git($d, 'init', '-q');
        git($d, 'add', '.');
        git($d, 'commit', '-qm', $name);
        return $d;
    };
    my $good = $mkext->('good');
    my @common = ('--c-root', $c, '--root', $root, '--keep-minuit');

    my ($rc, $out) = run('install', @common, '--no-default-extensions', '--extension', "good=$good\@main");
    is($rc, 0, 'fresh install') or diag $out;
    like($out, qr/link test passed \(1 extension library, every object linked\)/, '...with the link test');
    like(slurp("$root/etc/engine.json"), qr/"name" : "good"/, '...recording the extension');
    ok(-d "$root/.engine-previous", '...and keeping a rollback point');

    ($rc, $out) = run('install', @common);
    is($rc, 0, 'upgrade with no extension options') or diag $out;
    like($out, qr/updating the installed extensions: good/, '...updates the recorded extension, not the defaults');

    my $before = state($root, qw(lib include share etc));
    my $broken = $mkext->('broken', 1);
    ($rc, $out) = run('install', @common, '--no-default-extensions', '--extension', "good=$good\@main", '--extension', "broken=$broken\@main");
    is($rc, 1, 'an extension calling something nothing defines: the install fails');
    like($out, qr/the link test failed.*undefined reference to .core_model_that_is_gone/s, '...at the link test, naming the symbol');
    like($out, qr/restored the previous engine/, '...and says the old engine is back');
    is(state($root, qw(lib include share etc)), $before, '...byte for byte');
    ok(!-e "$c/extensions/broken", "...removing the checkout it had cloned");
    ok(-e "$c/extensions/good", '...but not one that was there before');
    is((run('install', @common))[0], 0, 'the next plain install works again');
}

done_testing();
