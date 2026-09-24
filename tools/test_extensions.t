#!/usr/bin/env perl
# Tests for tools/extensions.pl. Run: perl tools/test_extensions.t   (make extensions-selftest)
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path remove_tree);
use File::Basename qw(dirname);
use Cwd qw(abs_path);
use JSON::PP ();

my $HERE   = dirname(abs_path($0));
my $C_ROOT = abs_path("$HERE/..");
my $DRIVER = "$HERE/extensions.pl";
my $json   = JSON::PP->new->utf8->canonical;
my $CAN_BUILD = (system('command -v make >/dev/null 2>&1') == 0) && (system('command -v cc >/dev/null 2>&1') == 0);

sub slurp { open my $f, '<:raw', $_[0] or die "$_[0]: $!"; local $/; <$f> }
sub spew  { make_path(dirname($_[0])); open my $f, '>:raw', $_[0] or die "$_[0]: $!"; print {$f} $_[1]; close $f }
sub sh    { system(@_) == 0 or die "failed: @_" }

sub run {
    my (@args) = @_;
    my $out = qx{perl $DRIVER @{[ map { quotemeta } @args ]} 2>&1};
    return ($? >> 8, $out);
}

sub tree {
    my (%o) = @_;
    my $d = tempdir(CLEANUP => 1);
    make_path("$d/extensions", "$d/core/onefit-3.1");
    sh('cp', "$C_ROOT/extensions/extension.mk", "$d/extensions/");
    # --legacy: a core from before 5.0.0, whose version sat in its makefile
    if ($o{legacy}) {
        spew("$d/core/onefit-3.1/makefile", "LIBNUMBER=" . ($o{libnumber} // '4.0.4') . "\n");
    } else {
        spew("$d/libnumber.mk", "LIBNUMBER=" . ($o{libnumber} // '5.0.0') . "\n");
    }
    spew("$d/META-C.json", $o{base_text} // '{"BPP": {"function": "BPP(f,a,tau)"}}');
    return $d;
}

sub add_template {
    my ($c, $name, %manifest) = @_;
    $name //= 'example';
    my $dst = "$c/extensions/$name";
    sh('cp', '-R', "$C_ROOT/extensions/template", $dst);
    my $m = $json->decode(slurp("$dst/extension.json"));
    $m->{name} = $name;
    @$m{ keys %manifest } = values %manifest;
    spew("$dst/extension.json", $json->encode($m));
    return $dst;
}

sub install { my ($c, $root, @extra) = @_; return run('install', '--c-root', $c, '--root', $root, @extra) }

# ---- validation --------------------------------------------------------
{
    my ($rc, $out) = run('validate', "$C_ROOT/extensions/template");
    is($rc, 0, 'template validates');
    like($out, qr/provides ExampleGain/, '...and says what it provides');
}
{
    my $c = tree();
    my $d = add_template($c);
    my $m = $json->decode(slurp("$d/extension.json"));
    $m->{name} = 'other';
    spew("$d/extension.json", $json->encode($m));
    my ($rc, $out) = run('validate', $d, '--c-root', $c);
    is($rc, 1, 'name must match directory: rejected');
    like($out, qr/must equal its directory name/, '...with a clear message');
}
{
    my $c = tree();
    my $d = add_template($c, 'example', provides => ['ExampleGain', 'Ghost']);
    my ($rc, $out) = run('validate', $d, '--c-root', $c);
    is($rc, 1, 'provides/metadata mismatch rejected');
    like($out, qr/not in metadata: \['Ghost'\]/, '...naming the missing function');
}
{
    my $c = tree();
    my %cases = (
        'missing source'        => [{ sources => ['nope.c'] }, qr/source file not found/],
        'missing licence file'  => [{ license => { spdx => 'MIT', files => ['MISSING'], redistributable => JSON::PP::true } }, qr/licence file not found/],
        'non-boolean redistrib' => [{ license => { spdx => 'MIT', files => ['LICENSE'], redistributable => 'yes' } }, qr/redistributable must be true or false/],
        'bad extra_libs'        => [{ extra_libs => ['lapack'] }, qr/-l\/-L flags/],
        'bad source type'       => [{ sources => ['example.h'] }, qr/unsupported source type/],
        'declarations not in headers' => [{ declarations => ['other.h'] }, qr/declarations entry is not listed in headers: other\.h/],
        'bad fflags'            => [{ fflags => ['-std=legacy; rm -rf /'] }, qr/fflags entries must be plain compiler options/],
        'empty provides'        => [{ provides => [] }, qr/provides must not be empty/],
        'empty sources'         => [{ sources => [] }, qr/sources must not be empty/],
        'empty licence files'   => [{ license => { spdx => 'MIT', files => [], redistributable => JSON::PP::true } }, qr/license.files must list/],
    );
    for my $label (sort keys %cases) {
        my $d = add_template($c, 'case', %{ $cases{$label}[0] });
        my ($rc, $out) = run('validate', $d, '--c-root', $c);
        is($rc, 1, "$label: rejected");
        like($out, $cases{$label}[1], "$label: clear message");
        remove_tree($d);
    }
}
{
    my $c = tree();
    my $d = add_template($c, 'example', requires_base => '>=5.1');
    my ($rc, $out) = run('validate', $d, '--c-root', $c);
    is($rc, 1, 'requires_base not met: rejected');
    like($out, qr/requires base >=5\.1, this base is 5\.0\.0/, '...with both versions named');
    my $d2 = add_template($c, 'newer', requires_base => '>=5.0.0');
    is((run('validate', $d2, '--c-root', $c))[0], 0, 'requires_base met: accepted');
    # 5.0.0 renumbered 4.0.4 without changing what extensions use
    my $d3 = add_template($c, 'older', requires_base => '>=4.0.4');
    is((run('validate', $d3, '--c-root', $c))[0], 0, 'written for 4.x: accepted by a 5.x core');
}
{
    # same major only: a new major is not reached by >=
    my $c = tree(libnumber => '6.0.0');
    for my $req ('>=5.0.0', '>=4.0.4') {
        (my $n = "old$req") =~ s/\W//g;
        my $d = add_template($c, $n, requires_base => $req);
        my ($rc, $out) = run('validate', $d, '--c-root', $c);
        is($rc, 1, "requires_base $req on a 6.0.0 core: rejected");
        like($out, qr/written for core 5\.x .* this core is 6\.0\.0 .* raise its requires_base to '>=6\.0\.0'/,
            '...saying what to review and what to raise it to');
    }
}
{
    # a core from before libnumber.mk: the version is still read from its makefile
    my $c = tree(legacy => 1);
    my $d = add_template($c, 'example', requires_base => '>=4.0.4');
    is((run('validate', $d, '--c-root', $c))[0], 0, 'pre-5.0.0 core: version read from the core makefile');
}

# ---- set checks (all must fail before anything is built) ---------------
{
    my $c = tree();
    add_template($c, 'florence',     conflicts => ['florence-nag']);
    add_template($c, 'florence-nag', conflicts => ['florence']);
    my $root = tempdir(CLEANUP => 1);
    my ($rc, $out) = install($c, "$root/ofe");
    is($rc, 1, 'declared conflict refused');
    like($out, qr/'florence'.*conflicts with 'florence-nag'|'florence-nag'.*conflicts with 'florence'/, '...naming both');
    ok(!-e "$root/ofe", '...and nothing was built or created');
}
{
    my $c = tree();
    add_template($c, 'aaa');
    add_template($c, 'bbb');
    my ($rc, $out) = install($c, tempdir(CLEANUP => 1) . '/ofe');
    is($rc, 1, 'duplicate function across extensions refused');
    like($out, qr/provided by both 'aaa' and 'bbb'/, '...naming both');
}
{
    my $c = tree(base_text => '{"ExampleGain": {}}');
    add_template($c, 'aaa');
    my ($rc, $out) = install($c, tempdir(CLEANUP => 1) . '/ofe');
    is($rc, 1, 'redefining a base function refused');
    like($out, qr/redefines 'ExampleGain'/, '...naming it');
}

SKIP: {
    skip 'needs make and a C compiler', 53 unless $CAN_BUILD;

    # ---- install ------------------------------------------------------
    {
        my $c = tree();
        my $root = tempdir(CLEANUP => 1);
        is((install($c, $root))[0], 0, 'no extensions: install succeeds');
        like(slurp("$root/etc/extensions.mk"), qr/^EXTERNAL_MODEL_LIBS := \n/m, '...with empty link hook');
        is_deeply($json->decode(slurp("$c/META-CATALOG.json")), $json->decode(slurp("$c/META-C.json")), '...and a catalog equal to the base');
    }
    {
        my $c = tree();
        add_template($c, 'example', extra_libs => ['-lm']);
        my $root = tempdir(CLEANUP => 1);
        my $base_before = slurp("$c/META-C.json");
        my ($rc, $out) = install($c, $root, '--test');
        is($rc, 0, 'build + install + tests succeed') or diag $out;
        ok(-f "$root/lib/libonefit-ext-example.a", 'library installed');
        ok(-f "$root/include/ext/example/example.h", 'header installed');
        ok(-f "$root/share/extensions/example/LICENSE", 'licence installed');
        my $rroot = abs_path($root);
        my $mk = slurp("$root/etc/extensions.mk");
        like($mk, qr/-lonefit-ext-example -lm/, 'extensions.mk: library then extra_libs');
        like($mk, qr/-I\Q$rroot\E\/include\/ext\/example/, 'extensions.mk: include path');
        my $cat = $json->decode(slurp("$c/META-CATALOG.json"));
        ok(exists $cat->{ExampleGain} && exists $cat->{BPP}, 'catalog has base and extension functions');
        is(slurp("$c/META-C.json"), $base_before, 'base catalog never edited');
        is((install($c, $root))[0], 0, 're-running is a clean no-op');
    }
    {
        my $c = tree();
        my $d = add_template($c);
        my $root = tempdir(CLEANUP => 1);
        install($c, $root);
        remove_tree($d);
        is((install($c, $root))[0], 0, 'reinstall after removing the extension succeeds');
        unlike(slurp("$c/META-CATALOG.json"), qr/ExampleGain/, '...and it is gone from the catalog');
        unlike(slurp("$root/etc/extensions.mk"), qr/example/, '...and from extensions.mk');
    }

    # ---- what a fit needs: declarations + flags that compile ----------
    {
        my $c = tree();
        add_template($c);
        my $root = tempdir(CLEANUP => 1);
        is((install($c, $root))[0], 0, 'template installs');
        my $rroot = abs_path($root);
        like(slurp("$root/include/ext/extensions.h"), qr/#include "example\/example\.h"/, 'extensions.h declares the extension via its headers (default)');
        my ($flags) = slurp("$root/etc/extensions.mk") =~ /^EXTERNAL_MODEL_INCLUDES := (.*)$/m;
        like($flags, qr/-include \Q$rroot\E\/include\/ext\/extensions\.h/, 'extensions.mk force-includes it');
        my ($libs) = slurp("$root/etc/extensions.mk") =~ /^EXTERNAL_MODEL_LIBS := (.*)$/m;
        # Like a generated fit: never includes the extension's own header, and
        # is compiled so an undeclared function is an error.
        my $t = tempdir(CLEANUP => 1);
        spew("$t/fit.c", "int main(void){ return (int)ExampleGain(3.0, 2.0) - 6; }\n");
        my $cc = "cc -std=gnu99 -Werror=implicit-function-declaration -Wall $flags $t/fit.c -L$rroot/lib $libs -lm -o $t/fit 2>&1";
        my $out = qx{$cc};
        is($? >> 8, 0, 'a fit-style source using the extension function compiles and links') or diag $out;
        is(system("$t/fit"), 0, '...and runs correctly');
        unlike(qx{cc -std=gnu99 -Werror=implicit-function-declaration -Wall $t/fit.c -c -o /dev/null 2>&1}, qr/^$/, '(control: without the generated flags it does not compile)');
    }
    {
        my $c = tree();
        my $d = add_template($c);
        spew("$d/internal.h", "void ext_internal_(double *x);\n");
        my $m = $json->decode(slurp("$d/extension.json"));
        $m->{headers} = ['example.h', 'internal.h'];
        $m->{declarations} = ['example.h'];
        spew("$d/extension.json", $json->encode($m));
        my $root = tempdir(CLEANUP => 1);
        is((install($c, $root))[0], 0, 'install with declarations narrower than headers');
        my $h = slurp("$root/include/ext/extensions.h");
        like($h, qr/example\/example\.h/, 'declared header is included for fits');
        unlike($h, qr/internal\.h/, 'internal header is not');
        ok(-f "$root/include/ext/example/internal.h", '...but is still installed');
    }
    {
        my $c = tree();
        my $root = tempdir(CLEANUP => 1);
        install($c, $root);
        unlike(slurp("$root/etc/extensions.mk"), qr/-include/, 'no extensions: no force-include');
        ok(-f "$root/include/ext/extensions.h", '...but the header exists (harmless, keeps hooks uniform)');
    }

    # ---- the compilers extension.mk will use, even where make's own defaults are wrong ---
    {
        # GNU make defines FC as f77 and CC as cc by default, so a plain `FC ?=`
        # never applies: on macOS (no f77) every Fortran extension failed with
        # "f77: No such file or directory". Debian happens to link f77 to gfortran.
        my $dir = tempdir(CLEANUP => 1);
        spew("$dir/show.mk", "include $C_ROOT/extensions/extension.mk\nshow:\n\t\@echo \$(\$(WHAT))\n");
        my $var = sub {
            my ($what, $env) = @_;
            my $out = qx{cd $dir && $env make -s -f show.mk show WHAT=$what C_ROOT=. ROOT=. 2>&1};
            chomp $out;
            return $out;
        };
        my $fc = $var->('FC', '');
        is($fc, 'gfortran', 'FC defaults to gfortran, not make\'s built-in f77');
        my $fc_env = $var->('FC', 'FC=myfortran');
        is($fc_env, 'myfortran', '...and an FC the caller sets still wins');
        my $cc = $var->('CC', 'CC=mycc');
        is($cc, 'mycc', 'a caller-set CC also still wins');
    }

    # ---- legacy Fortran: fflags silences the deleted-feature warnings ---
    SKIP: {
        skip 'needs gfortran', 4 unless system('command -v gfortran >/dev/null 2>&1') == 0;
        my $legacy = "      REAL FUNCTION LEGSUM(SET)\n      REAL SET\n      LEGSUM = 0.\n      DO K=1,SET\n      LEGSUM = LEGSUM + K\n      ENDDO\n      RETURN\n      END\n";
        my $build = sub {
            my (%extra) = @_;
            my $c = tree();
            my $d = add_template($c, 'legacy', %extra);
            spew("$d/leg.f", $legacy);
            my $m = $json->decode(slurp("$d/extension.json"));
            push @{ $m->{sources} }, 'leg.f';
            @$m{ keys %extra } = values %extra;
            spew("$d/extension.json", $json->encode($m));
            return install($c, tempdir(CLEANUP => 1) . '/ofe');
        };
        my ($rc, $out) = $build->();
        is($rc, 0, 'legacy Fortran builds without fflags') or diag $out;
        like($out, qr/Warning: .*DO loop/, '...but gfortran warns about the deleted feature');
        my ($rc2, $out2) = $build->(fflags => ['-std=legacy']);
        is($rc2, 0, 'the same source builds with fflags -std=legacy') or diag $out2;
        unlike($out2, qr/Warning/, '...and gfortran no longer warns');
    }

    # ---- catalog order and format ------------------------------------
    {
        # Deliberately not alphabetical: the catalog must keep the base file's
        # order, then append extension functions, keeping each entry's field order.
        my $base = '{"Zeta": {"devision": "d", "function": "f", "call": "c"}, "Alpha": {"devision": "d", "function": "f", "call": "c"}}';
        my $c = tree(base_text => $base);
        add_template($c);
        my $root = tempdir(CLEANUP => 1);
        is((install($c, $root))[0], 0, 'install with an unsorted base catalog');
        my $text = slurp("$c/META-CATALOG.json");
        my @order = $text =~ /^    "([A-Za-z]+)": \{/mg;
        is_deeply(\@order, [qw(Zeta Alpha ExampleGain)], 'top-level order: base order kept, extensions appended');
        like($text, qr/"devision": "d",\n\s+"function": "f",\n\s+"call": "c"/, 'entry field order kept (not alphabetical)');
        like($text, qr/\n\z/, 'ends with a newline');
    }
    {
        my $c = tree(base_text => qq({"Uml": {"description": "caf\x{c3}\x{a9} \\"quoted\\" \\\\ back"}}));
        my $root = tempdir(CLEANUP => 1);
        install($c, $root);
        my $cat = $json->decode(slurp("$c/META-CATALOG.json"));
        is($cat->{Uml}{description}, "caf\x{e9} \"quoted\" \\ back", 'non-ASCII, quotes and backslashes round-trip');
    }

    # ---- makefile handling / licence paths / legacy -------------------
    {
        my $c = tree();
        my $d = add_template($c);
        spew("$d/Makefile", "install:\n\ttouch \$(ROOT)/HIJACKED\n");
        my $root = tempdir(CLEANUP => 1);
        is((install($c, $root))[0], 0, 'extension with a stray Makefile installs');
        ok(!-e "$root/HIJACKED", '...and the Makefile the manifest does not name did not run');
        ok(-f "$root/lib/libonefit-ext-example.a", '...shared rules built it');
        my $m = $json->decode(slurp("$d/extension.json"));
        $m->{makefile} = 'Makefile';
        spew("$d/extension.json", $json->encode($m));
        is((install($c, $root))[0], 0, 'explicitly named makefile installs');
        ok(-e "$root/HIJACKED", '...and it is the one that ran');
    }
    {
        my $c = tree();
        my $d = add_template($c);
        spew("$d/sub/NOTICE", 'second notice');
        my $m = $json->decode(slurp("$d/extension.json"));
        $m->{license}{files} = ['LICENSE', 'NOTICE', 'sub/NOTICE'];
        spew("$d/extension.json", $json->encode($m));
        my $root = tempdir(CLEANUP => 1);
        is((install($c, $root))[0], 0, 'nested licence files install');
        is(slurp("$root/share/extensions/example/sub/NOTICE"), 'second notice', 'nested licence keeps its path');
        isnt(slurp("$root/share/extensions/example/NOTICE"), 'second notice', '...and does not overwrite the top-level one');
    }
    {
        my $c = tree();
        spew("$c/extensions/old/Makefile", "install:\n\tfalse\n");
        my ($rc, $out) = install($c, tempdir(CLEANUP => 1) . '/ofe');
        is($rc, 0, 'legacy bundle is skipped, not fatal');
        like($out, qr/skipping legacy bundle old/, '...and reported');
        my ($lrc, $lout) = run('list', '--c-root', $c);
        like($lout, qr/old  \(legacy bundle/, 'list shows the legacy bundle');
    }
}

# ---- fetch ---------------------------------------------------------------
my $HAVE_GIT = system('command -v git >/dev/null 2>&1') == 0;
SKIP: {
    skip 'needs git', 40 unless $HAVE_GIT;

    my $git = sub { my $dir = shift; sh('git', '-C', $dir, '-c', 'user.name=t', '-c', 'user.email=t@t', @_) };
    my $mkrepo = sub {
        my ($content) = @_;
        my $r = tempdir(CLEANUP => 1);
        sh('git', 'init', '-q', '-b', 'main', $r);
        spew("$r/extension.json", $content);
        $git->($r, 'add', '.');
        $git->($r, 'commit', '-q', '-m', 'one');
        return $r;
    };
    my $fetch = sub { my ($c, @a) = @_; return run('fetch', '--c-root', $c, @a) };

    {
        my $c = tree();
        my ($rc, $out) = $fetch->($c, '--extension', 'nope');
        is($rc, 1, 'unknown name (not in registry, no URL) fails');
        like($out, qr/unknown extension 'nope'.*--extension nope=URL/s, '...and says how to give a URL');
        my ($rc2, $out2) = $fetch->($c, '--extension', '../evil');
        is($rc2, 1, 'a path-like name is rejected (it would become a directory)');
        like($out2, qr/name must match/, '...with a clear message');
        my ($rc3) = $fetch->($c, '--no-default-extensions');
        is($rc3, 0, 'nothing requested and defaults off: succeeds');
        ok(!glob("$c/extensions/*/") , '...and fetches nothing');
    }
    {
        my $repo = $mkrepo->('{"v":1}');
        my $c = tree();
        my ($rc, $out) = $fetch->($c, '--no-default-extensions', '--extension', "mine=$repo");
        is($rc, 0, 'NAME=URL clones into extensions/NAME') or diag $out;
        like(slurp("$c/extensions/mine/extension.json"), qr/"v":1/, '...with the repo content');

        spew("$repo/extension.json", '{"v":2}');
        $git->($repo, 'commit', '-q', '-am', 'two');
        my ($rc2) = $fetch->($c, '--no-default-extensions', '--extension', "mine=$repo");
        is($rc2, 0, 'a second fetch succeeds');
        like(slurp("$c/extensions/mine/extension.json"), qr/"v":2/, '...and picks up the new commit (not the stale local branch)');

        $git->($repo, 'tag', 'v2');
        spew("$repo/extension.json", '{"v":3}');
        $git->($repo, 'commit', '-q', '-am', 'three');
        my ($rc3) = $fetch->($c, '--no-default-extensions', '--extension', "mine=$repo\@v2");
        is($rc3, 0, 'NAME=URL@REF fetches that ref');
        like(slurp("$c/extensions/mine/extension.json"), qr/"v":2/, '...and lands on the tag, not the branch tip');
    }
    {
        # registry default: optional
        my $repo = $mkrepo->('{"v":1}');
        my $c = tree();
        spew("$c/extensions/registry.json", $json->encode({ schema => 1, extensions => {
            good => { repo => $repo, default => JSON::PP::true },
            gone => { repo => '/nonexistent/repo.git', default => JSON::PP::true },
            opt  => { repo => $repo },
        } }));
        my ($rc, $out) = $fetch->($c);
        is($rc, 0, 'an unreachable DEFAULT extension only warns') or diag $out;
        like($out, qr/WARNING: could not fetch default extension gone/, '...and says so');
        ok(-f "$c/extensions/good/extension.json", 'the reachable default was fetched');
        ok(!-e "$c/extensions/opt", 'a non-default registry entry is not fetched unless named');
        my ($rc2, $out2) = $fetch->($c, '--extension', 'gone');
        is($rc2, 1, 'the same unreachable extension, NAMED, is an error');
        like($out2, qr/could not fetch extension gone/, '...and says so');
        my ($rc3) = $fetch->($c, '--extension', 'opt', '--no-default-extensions');
        is($rc3, 0, 'a registry name resolves through its URL');
        ok(-f "$c/extensions/opt/extension.json" && !-e "$c/extensions/good/x", '...fetching only what was named');
    }
    {
        my $repo = $mkrepo->('{"v":1}');
        chomp(my $sha = qx{git -C $repo rev-parse HEAD});
        my $c = tree();
        my $out = qx{perl $DRIVER fetch --c-root $c --no-default-extensions --extension mine=$repo --json 2>/dev/null};
        is($? >> 8, 0, 'fetch --json succeeds');
        my $got = eval { $json->decode($out) };
        ok($got && @$got == 1, '...stdout is exactly one JSON array (git output stays on stderr)') or diag $out;
        is_deeply($got, [{ name => 'mine', repo => $repo, ref => 'main', commit => $sha }], '...naming the extension, repo, ref and resolved commit');
        my $none = qx{perl $DRIVER fetch --c-root $c --no-default-extensions --json 2>/dev/null};
        is_deeply($json->decode($none), [], 'nothing fetched: an empty array');
    }
    {
        # a named extension that declares a conflict with a default replaces it
        my $dflt = $mkrepo->('{"v":"default"}');
        my $repl = $mkrepo->('{"conflicts":["dflt"]}');
        my $other = $mkrepo->('{"v":"other-default"}');
        my $reg = sub { my ($c) = @_; spew("$c/extensions/registry.json", $json->encode({ schema => 1, extensions => {
            dflt  => { repo => $dflt,  default => JSON::PP::true },
            other => { repo => $other, default => JSON::PP::true },
        } })) };

        my $c = tree(); $reg->($c);
        my ($rc, $out) = $fetch->($c, '--extension', "repl=$repl");
        is($rc, 0, 'a named extension that conflicts with a default: fetch succeeds') or diag $out;
        ok(-f "$c/extensions/repl/extension.json", '...the named extension is fetched');
        ok(!-e "$c/extensions/dflt", '...the conflicting default is NOT fetched');
        like($out, qr/skipping default extension dflt: replaced by repl/, '...and the skip is reported');
        ok(-f "$c/extensions/other/extension.json", '...a default it does not conflict with is still fetched');

        my $c2 = tree(); $reg->($c2);
        my ($rc2, $out2) = $fetch->($c2, '--extension', "repl=$repl", '--no-default-extensions');
        is($rc2, 0, 'the same with defaults already off');

        # a conflicting folder left by an earlier install is refused, never deleted
        my $c3 = tree(); $reg->($c3);
        $fetch->($c3, '--extension', 'dflt');
        spew("$c3/extensions/dflt/local-change.txt", 'mine');
        my ($rc3, $out3) = $fetch->($c3, '--extension', "repl=$repl");
        is($rc3, 1, 'a leftover installed folder that conflicts is refused');
        like($out3, qr/'repl' conflicts with the installed 'dflt' - remove extensions\/dflt/, '...naming both and the fix');
        ok(-f "$c3/extensions/dflt/local-change.txt", '...and nothing was deleted');
    }
    {
        my $c = tree();
        spew("$c/extensions/registry.json", $json->encode({ schema => 1, extensions => {
            florence => { repo => 'https://github.com/fitteia/onefite-ext-florence.git' } } }));
        my ($rc, $out) = $fetch->($c, '--transport', 'ssh', '--no-default-extensions', '--extension', 'florence');
        like($out, qr/git\@github\.com:fitteia\/onefite-ext-florence\.git/, '--transport ssh rewrites a registry https URL');
    }
}

done_testing();
