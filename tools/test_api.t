#!/usr/bin/env perl
# Tests for tools/api.pl. Run: perl tools/test_api.t   (make api-selftest)
use strict;
use warnings;
use Test::More;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
use File::Basename qw(dirname);
use Cwd qw(abs_path);

my $HERE   = dirname(abs_path($0));
my $DRIVER = "$HERE/api.pl";

sub slurp { open my $f, '<:raw', $_[0] or die "$_[0]: $!"; local $/; <$f> }
sub spew  { make_path(dirname($_[0])); open my $f, '>:raw', $_[0] or die "$_[0]: $!"; print {$f} $_[1]; close $f }

sub run {
    my ($cmd, $c) = @_;
    my $out = qx{perl $DRIVER $cmd --c-root \Q$c\E 2>&1};
    return ($? >> 8, $out);
}

sub libnumber { (slurp("$_[0]/libnumber.mk") =~ /^LIBNUMBER=(\S+)/m)[0] }

# A minimal onefite-c-code: libnumber.mk, the install-fitteia header list, and
# one header in each of the three installed places.
sub tree {
    my $c = tempdir(CLEANUP => 1);
    spew("$c/libnumber.mk", "# the core version\nLIBNUMBER=5.0.0\n");
    spew("$c/core/onefit-3.1/makefile",
        "install-fitteia: Lib fft\n\tinstall -d \$(BINDIR)\n\tinstall -m 0644 core.h \$(INCLUDEDIR)\n");
    spew("$c/core/onefit-3.1/core.h", <<'H');
/* the core */
#define NMAX 100
#define SQ(x) ((x)*(x))
typedef struct { double x; double y; } Ponto;
static int helper(int k)
{
    return k + 1;
}
double core_fn(double a, double b);
H
    spew("$c/core/onefit-3.1/internal.h", "double not_installed(double);\n");
    spew("$c/core/onefit-3.1/modelos/model.h", "double model(double t);\n");
    spew("$c/local/BPP.h", "/** BPP.h **/\ndouble BPP(double f,double a,double tauc);\n");
    return $c;
}

sub edit { my ($p, $from, $to) = @_; my $s = slurp($p); $s =~ s/\Q$from\E/$to/ or die "no '$from' in $p"; spew($p, $s) }

{
    my $c = tree();
    my ($rc, $out) = run('check', $c);
    is($rc, 1, 'no snapshot yet: check asks for one');
    like($out, qr/no API snapshot yet .* make api-accept/, '...and says how');

    ($rc, $out) = run('accept', $c);
    is($rc, 0, 'accept records the first snapshot');
    is(libnumber($c), '5.0.0', '...without changing LIBNUMBER');
    my $snap = slurp("$c/api/core-api.txt");
    like($snap, qr/^# LIBNUMBER 5\.0\.0$/m, '...for the current LIBNUMBER');
    like($snap, qr/^core\/onefit-3\.1\/core\.h: double core_fn\(double a,double b\);$/m, 'a declaration, normalised');
    like($snap, qr/^core\/onefit-3\.1\/core\.h: #define NMAX 100$/m, 'a constant macro, in full');
    like($snap, qr/^core\/onefit-3\.1\/core\.h: #define SQ\(x\)\.\.\.$/m, 'a function-like macro, name and parameters only');
    like($snap, qr/^core\/onefit-3\.1\/core\.h: typedef struct\{double x;double y;\}Ponto;$/m, 'a struct, with its layout');
    like($snap, qr/^core\/onefit-3\.1\/core\.h: static int helper\(int k\)\{\.\.\.\}$/m, 'a function defined in a header: signature only');
    like($snap, qr/^core\/onefit-3\.1\/modelos\/model\.h: /m, 'modelos headers count');
    like($snap, qr/^local\/BPP\.h: /m, 'local headers count');
    unlike($snap, qr/not_installed/, 'a core header that is not installed does not');
    unlike($snap, qr/the core/, 'comments do not');

    is((run('check', $c))[0], 0, 'unchanged: check passes');

    # changes extensions cannot see
    edit("$c/core/onefit-3.1/core.h", 'double core_fn(double a, double b);', "double   core_fn( double a,\n   double b ); /* moved */");
    edit("$c/core/onefit-3.1/core.h", 'return k + 1;', 'return k + 2;');
    edit("$c/core/onefit-3.1/core.h", '#define SQ(x) ((x)*(x))', '#define SQ(x) (x)*(x)');
    edit("$c/core/onefit-3.1/internal.h", 'double not_installed(double);', 'int not_installed(void);');
    is((run('check', $c))[0], 0, 'spacing, comments, header function bodies, macro bodies, non-installed headers: no change');
}
{
    # an addition needs a new minor
    my $c = tree();
    run('accept', $c);
    spew("$c/local/NEW.h", "double NEWMODEL(double x);\n");
    my ($rc, $out) = run('check', $c);
    is($rc, 1, 'a new declaration: check stops');
    like($out, qr/added: +local\/NEW\.h: double NEWMODEL\(double x\);/, '...naming it');
    like($out, qr/needs LIBNUMBER 5\.1\.0 \(it is 5\.0\.0\).*make api-accept/s, '...asking for a new minor');
    is(libnumber($c), '5.0.0', 'check changes nothing');
    ($rc, $out) = run('accept', $c);
    is($rc, 0, 'accept');
    like($out, qr/LIBNUMBER: 5\.0\.0 -> 5\.1\.0/, '...raises LIBNUMBER');
    is(libnumber($c), '5.1.0', '...in libnumber.mk');
    like(slurp("$c/libnumber.mk"), qr/^# the core version$/m, '...keeping the rest of the file');
    like(slurp("$c/api/core-api.txt"), qr/^# LIBNUMBER 5\.1\.0$/m, '...and records the snapshot for 5.1.0');
    is((run('check', $c))[0], 0, 'then check passes');
}
{
    # a removal or change needs a new major
    my $c = tree();
    run('accept', $c);
    edit("$c/core/onefit-3.1/core.h", 'double core_fn(double a, double b);', 'double core_fn(double a, double b, double c);');
    my ($rc, $out) = run('check', $c);
    is($rc, 1, 'a changed signature: check stops');
    like($out, qr/removed: .*core_fn\(double a,double b\);.*added: .*core_fn\(double a,double b,double c\);/s, '...showing old and new');
    like($out, qr/removed or changed -> needs LIBNUMBER 6\.0\.0/, '...asking for a new major');
    run('accept', $c);
    is(libnumber($c), '6.0.0', 'accept sets 6.0.0');

    my $c2 = tree();
    run('accept', $c2);
    edit("$c2/core/onefit-3.1/core.h", 'double x; double y;', 'double x; double y; double z;');
    like((run('check', $c2))[1], qr/needs LIBNUMBER 6\.0\.0/, 'a struct layout change: new major');

    my $c3 = tree();
    run('accept', $c3);
    unlink "$c3/core/onefit-3.1/modelos/model.h";
    like((run('check', $c3))[1], qr/removed: .*model\.h.*needs LIBNUMBER 6\.0\.0/s, 'a removed header: new major');

    my $c4 = tree();
    run('accept', $c4);
    edit("$c4/core/onefit-3.1/core.h", '#define NMAX 100', '#define NMAX 200');
    like((run('check', $c4))[1], qr/needs LIBNUMBER 6\.0\.0/, 'a changed constant: new major');
}
{
    # LIBNUMBER set by hand
    my $c = tree();
    run('accept', $c);
    spew("$c/local/NEW.h", "double NEWMODEL(double x);\n");
    edit("$c/libnumber.mk", 'LIBNUMBER=5.0.0', 'LIBNUMBER=6.0.0');
    my ($rc, $out) = run('check', $c);
    is($rc, 1, 'already raised by hand: check still asks to record the API');
    like($out, qr/already 6\.0\.0 \(needs at least 5\.1\.0\).*make api-accept/s, '...saying the number is enough');
    run('accept', $c);
    is(libnumber($c), '6.0.0', 'accept keeps a higher number set by hand');

    my $c2 = tree();
    run('accept', $c2);
    edit("$c2/libnumber.mk", 'LIBNUMBER=5.0.0', 'LIBNUMBER=5.0.1');
    ($rc, $out) = run('check', $c2);
    is($rc, 1, 'LIBNUMBER changed but the API did not: check stops');
    like($out, qr/recorded for 5\.0\.0, and the API did not change/, '...and says so');
}
{
    my $c = tree();
    spew("$c/core/onefit-3.1/makefile", "all:\n\techo\n");
    my ($rc, $out) = run('check', $c);
    is($rc, 2, 'no install-fitteia header list: error, not a silent empty API');
    like($out, qr/cannot find the installed header list/, '...saying what is missing');
}

done_testing();
