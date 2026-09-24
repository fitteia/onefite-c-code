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
    spew("$d/core/onefit-3.1/makefile", "LIBNUMBER=" . ($o{libnumber} // '4.0.4') . "\n");
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
    my $d = add_template($c, 'example', requires_base => '>=5.0');
    my ($rc, $out) = run('validate', $d, '--c-root', $c);
    is($rc, 1, 'requires_base not met: rejected');
    like($out, qr/requires base >=5\.0, this base is 4\.0\.4/, '...with both versions named');
    my $d2 = add_template($c, 'newer', requires_base => '>=4.0.4');
    is((run('validate', $d2, '--c-root', $c))[0], 0, 'requires_base met: accepted');
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
    skip 'needs make and a C compiler', 30 unless $CAN_BUILD;

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

done_testing();
