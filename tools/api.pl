#!/usr/bin/env perl
# The core's API check: notices when something extensions may use changes,
# and says which LIBNUMBER that needs (README.md, "Version").
#
# The API is what the installed headers declare - the only thing an extension
# can #include: core/onefit-3.1's installed headers, and every header of
# core/onefit-3.1/modelos and local. Each declaration is recorded, normalised
# (comments and spacing ignored), in api/core-api.txt together with the
# LIBNUMBER it belongs to:
#   - constant macros and struct/union/enum/typedef bodies in full (their
#     values and layout are API);
#   - function-like macros and functions defined in a header (static helpers):
#     name and parameters only, since their body is code compiled into each
#     fit, not something extensions call into.
#
#   perl tools/api.pl check  [--c-root DIR]   exit 0: consistent; 1: act
#   perl tools/api.pl accept [--c-root DIR]   record the API, set LIBNUMBER
#
# check compares the headers with the snapshot. Only additions: a new minor
# (5.1.0) is needed; anything removed or changed: a new major (6.0.0). accept
# writes the new snapshot and raises LIBNUMBER in libnumber.mk to what the
# change needs (a higher number set by hand is kept). Commit both files,
# saying in the message what changed.
#
# Core Perl only, so it runs anywhere onefite-c-code builds (no compiler).
use strict;
use warnings;
use File::Spec;
use Getopt::Long qw(GetOptionsFromArray);

my $SNAPSHOT = 'api/core-api.txt';

sub fail { print STDERR "error: $_[0]\n"; exit 2 }

sub slurp {
    my ($p) = @_;
    open my $fh, '<', $p or fail("cannot read $p: $!");
    local $/;
    return scalar <$fh>;
}

sub spew {
    my ($p, $text) = @_;
    open my $fh, '>', $p or fail("cannot write $p: $!");
    print {$fh} $text;
    close $fh or fail("cannot write $p: $!");
}

# The headers `make install` puts in include/: the core list from the
# install-fitteia rule, plus every header of modelos and local.
sub installed_headers {
    my ($c) = @_;
    my $mk = slurp("$c/core/onefit-3.1/makefile");
    my ($list) = $mk =~ /^install-fitteia:.*?\n(?:\t.*\n)*?\tinstall -m 0644 ((?:\S+\.h\s+)+)\$\(INCLUDEDIR\)/m
        or fail("cannot find the installed header list in core/onefit-3.1/makefile (install-fitteia)");
    my @h = map { "core/onefit-3.1/$_" } split ' ', $list;
    for my $dir ('core/onefit-3.1/modelos', 'local') {
        opendir my $dh, "$c/$dir" or fail("cannot read $c/$dir: $!");
        push @h, map { "$dir/$_" } sort grep { /\.h$/ } readdir $dh;
        closedir $dh;
    }
    return @h;
}

sub squash {
    my ($s) = @_;
    $s =~ s/\s+/ /g;
    $s =~ s/^ | $//g;
    $s =~ s/ ?([(),;*\[\]{}=]) ?/$1/g;
    return $s;
}

# Normalised declarations of one header, as "file: declaration" lines.
sub declarations {
    my ($file, $text) = @_;
    $text =~ s{/\*.*?\*/}{ }gs;
    $text =~ s{//[^\n]*}{}g;
    $text =~ s/\\\n/ /g;
    my (@out, $code);
    for my $line (split /\n/, $text) {
        if ($line =~ /^\s*#\s*define\s+(\w+\([^)]*\))/) {
            push @out, '#define ' . squash($1) . '...';   # function-like: name and parameters
        } elsif ($line =~ /^\s*#\s*define\s+(.*)$/) {
            push @out, '#define ' . squash($1);
        } elsif ($line =~ /^\s*#/) {
            next;   # includes and conditionals: both branches' declarations count
        } else {
            $code .= "$line\n";
        }
    }
    $code //= '';
    my ($depth, $stmt) = (0, '');
    for my $ch (split //, $code) {
        $stmt .= $ch;
        if ($ch eq '{') {
            $depth++;
        } elsif ($ch eq '}') {
            $depth--;
            if ($depth == 0 && $stmt =~ /^\s*[^={]*\)\s*\{/s) {
                (my $sig = $stmt) =~ s/\{.*//s;
                push @out, squash($sig) . '{...}';
                $stmt = '';
            }
        } elsif ($ch eq ';' && $depth == 0) {
            my $s = squash($stmt);
            push @out, $s if $s ne ';';
            $stmt = '';
        }
    }
    return map { "$file: $_" } @out;
}

sub current_api {
    my ($c) = @_;
    my %seen;
    for my $h (installed_headers($c)) {
        $seen{$_} = 1 for declarations($h, slurp("$c/$h"));
    }
    return [ sort keys %seen ];
}

sub libnumber {
    my ($c) = @_;
    my ($v) = slurp("$c/libnumber.mk") =~ /^LIBNUMBER\s*=\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$/m
        or fail("no LIBNUMBER=X.Y.Z in $c/libnumber.mk");
    return $v;
}

sub read_snapshot {
    my ($c) = @_;
    my $p = "$c/$SNAPSHOT";
    return (undef, undef) unless -f $p;
    my ($ver, @api);
    for (split /\n/, slurp($p)) {
        if (/^# LIBNUMBER (\S+)$/) { $ver = $1 }
        elsif (/\S/ && !/^#/)      { push @api, $_ }
    }
    return ($ver, \@api);
}

sub cmp_ver {
    my @a = split /\./, $_[0];
    my @b = split /\./, $_[1];
    for my $i (0 .. 2) { return $a[$i] <=> $b[$i] if $a[$i] != $b[$i] }
    return 0;
}

# What differs, and the smallest LIBNUMBER after $from that it needs.
sub compare {
    my ($old, $new, $from) = @_;
    my %o = map { $_ => 1 } @$old;
    my %n = map { $_ => 1 } @$new;
    my @removed = grep { !$n{$_} } @$old;
    my @added   = grep { !$o{$_} } @$new;
    my ($ma, $mi) = split /\./, $from;
    my $need = @removed ? join('.', $ma + 1, 0, 0)
             : @added   ? join('.', $ma, $mi + 1, 0)
             :            $from;
    return (\@removed, \@added, $need);
}

sub show_diff {
    my ($removed, $added) = @_;
    my @lines = ((map { "  removed: $_" } @$removed), (map { "  added:   $_" } @$added));
    print "$_\n" for @lines[0 .. ($#lines < 39 ? $#lines : 39)];
    print "  ... and " . (@lines - 40) . " more\n" if @lines > 40;
}

sub opts {
    my @args = @_;
    my %o = (c_root => '.');
    GetOptionsFromArray(\@args, 'c-root=s' => \$o{c_root}) or exit 2;
    $o{c_root} = File::Spec->rel2abs($o{c_root});
    fail("$o{c_root} is not onefite-c-code (no libnumber.mk)") unless -f "$o{c_root}/libnumber.mk";
    return \%o;
}

sub cmd_check {
    my $o = opts(@_);
    my $c = $o->{c_root};
    my $have = libnumber($c);
    my $api = current_api($c);
    my ($snap_ver, $snap) = read_snapshot($c);
    unless ($snap) {
        print "no API snapshot yet ($SNAPSHOT) - run: make api-accept\n";
        return 1;
    }
    my ($removed, $added, $need) = compare($snap, $api, $snap_ver);
    if (!@$removed && !@$added) {
        return 0 if $have eq $snap_ver;
        print "LIBNUMBER is $have but the API snapshot was recorded for $snap_ver, and the API did "
            . "not change - record it with: make api-accept (or set LIBNUMBER back to $snap_ver)\n";
        return 1;
    }
    print "core API changed since $snap_ver:\n";
    show_diff($removed, $added);
    my $why = @$removed ? 'something extensions may use was removed or changed'
                        : 'something was added';
    if (cmp_ver($have, $need) >= 0) {
        print "$why; LIBNUMBER is already $have (needs at least $need).\n"
            . "record this API with: make api-accept\n";
    } else {
        print "$why -> needs LIBNUMBER $need (it is $have).\n"
            . "run: make api-accept   (sets LIBNUMBER=$need and records the new API)\n";
    }
    return 1;
}

sub cmd_accept {
    my $o = opts(@_);
    my $c = $o->{c_root};
    my $have = libnumber($c);
    my ($snap_ver, $snap) = read_snapshot($c);
    my $api = current_api($c);
    my $new = $have;
    if ($snap) {
        my ($removed, $added, $need) = compare($snap, $api, $snap_ver);
        show_diff($removed, $added) if @$removed || @$added;
        if (cmp_ver($have, $need) < 0) {
            my $mk = slurp("$c/libnumber.mk");
            $mk =~ s/^LIBNUMBER\s*=.*$/LIBNUMBER=$need/m;
            spew("$c/libnumber.mk", $mk);
            $new = $need;
            print "LIBNUMBER: $have -> $need (libnumber.mk)\n";
        }
    }
    mkdir "$c/api" unless -d "$c/api";
    spew("$c/$SNAPSHOT",
        "# onefite-c-code core API: what the installed headers declare.\n"
        . "# Written by `make api-accept`, checked by `make api-check` (tools/api.pl).\n"
        . "# LIBNUMBER $new\n"
        . join('', map { "$_\n" } @$api));
    print "recorded the core API for LIBNUMBER $new in $SNAPSHOT (" . scalar(@$api) . " declarations)\n"
        . "commit libnumber.mk and $SNAPSHOT together, saying in the message what changed and why.\n";
    return 0;
}

my $cmd = shift // '';
my %cmds = (check => \&cmd_check, accept => \&cmd_accept);
my $run = $cmds{$cmd} or do {
    print STDERR "usage: $0 check|accept [--c-root DIR]\n";
    exit 2;
};
exit $run->(@ARGV);
