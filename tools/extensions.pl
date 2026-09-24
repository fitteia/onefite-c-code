#!/usr/bin/env perl
# Build and register onefite extensions (see extensions/README.md).
#
#   extensions.pl list      [--c-root DIR]
#   extensions.pl validate  PATH [--c-root DIR]
#   extensions.pl install   --root DIR [--c-root DIR] [--test] [--include-template]
#
# `install` validates every extensions/<name>/extension.json, refuses
# conflicting or duplicate function sets, builds each with
# extensions/extension.mk (or the Makefile its manifest names), and writes the
# only two things a runtime reads:
#
#   <root>/etc/extensions.mk    EXTERNAL_MODEL_LIBS / EXTERNAL_MODEL_INCLUDES
#   <c-root>/META-CATALOG.json  META-C.json + every extension's functions
#
# META-C.json itself is never modified. Plain perl + core modules only (perl
# is already a declared dependency of onefite; python is not).
use strict;
use warnings;
use B ();
use Cwd qw(abs_path getcwd);
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Spec ();
use Getopt::Long qw(GetOptionsFromArray);
use JSON::PP ();

my %SOURCE_SUFFIX = map { $_ => 1 } qw(.c .f);
my %SKIP_DIRS     = (template => 1);

sub fail { die "error: @_\n" }

sub slurp {
    my ($p) = @_;
    open my $fh, '<:raw', $p or fail("cannot read $p: $!");
    local $/;
    my $t = <$fh>;
    return $t;
}

sub spew {
    my ($p, $text) = @_;
    open my $fh, '>:raw', $p or fail("cannot write $p: $!");
    print {$fh} $text;
    close $fh or fail("cannot write $p: $!");
}

sub is_string { my ($v) = @_; return defined $v && !ref $v && (B::svref_2object(\$v)->FLAGS & B::SVp_POK) && !(B::svref_2object(\$v)->FLAGS & (B::SVp_IOK | B::SVp_NOK)) }
sub is_list_of_strings { my ($v) = @_; return ref $v eq 'ARRAY' && !grep { !is_string($_) } @$v }
sub is_bool { JSON::PP::is_bool($_[0]) }

# JSON::PP does not remember key order. To keep the catalog in the order it
# has today (base file order, extension functions appended, each entry's
# fields in their usual order) every key string is ranked by its first
# appearance in the source texts, and sort_by uses that rank.
my %RANK;
sub note_key_order {
    my ($text) = @_;
    while ($text =~ /("(?:[^"\\]|\\.)*")(\s*:)?/g) {
        next unless defined $2;
        my $key = JSON::PP->new->allow_nonref->utf8->decode($1);
        $RANK{$key} //= scalar keys %RANK;
    }
}

sub parse_json {
    my ($text, $where) = @_;
    my $data = eval { JSON::PP->new->utf8->decode($text) };
    fail("$where: invalid JSON: " . ($@ =~ s/ at .*//sr)) unless defined $data;
    return $data;
}

sub encode_catalog {
    my ($data) = @_;
    my $json = JSON::PP->new->utf8->pretty->indent_length(4)->space_before(0)->sort_by(sub {
        my ($a, $b) = ($JSON::PP::a, $JSON::PP::b);
        return (($RANK{$a} // 1e9) <=> ($RANK{$b} // 1e9)) || ($a cmp $b);
    });
    return $json->encode($data);
}

sub need {
    my ($cond, $where, $msg) = @_;
    fail("$where: $msg") unless $cond;
}

sub load_extension {
    my ($path, $allow_template_name) = @_;
    my $where = "$path/extension.json";
    need(-f $where, $path, 'no extension.json');
    my $data = parse_json(slurp($where), $where);
    need(ref $data eq 'HASH', $where, 'root must be an object');
    need(defined $data->{schema} && !ref $data->{schema} && $data->{schema} eq '1', $where, 'schema must be 1');
    for my $key (qw(name version provides sources metadata license)) {
        need(exists $data->{$key}, $where, "missing required field '$key'");
    }
    my $name = $data->{name};
    need(is_string($name) && scalar($name =~ /^[a-z][a-z0-9_-]*$/), $where, 'name must match [a-z][a-z0-9_-]*');
    (my $dir = $path) =~ s{/+$}{};
    $dir =~ s{.*/}{};
    unless ($allow_template_name && $SKIP_DIRS{$dir}) {
        need($name eq $dir, $where, "name '$name' must equal its directory name '$dir'");
    }
    need(is_string($data->{version}), $where, 'version must be a string');
    for my $key (qw(provides sources headers conflicts extra_libs)) {
        next unless exists $data->{$key};
        need(is_list_of_strings($data->{$key}), $where, "$key must be a list of strings");
    }
    need(scalar(@{ $data->{provides} }), $where, 'provides must not be empty');
    need(scalar(@{ $data->{sources} }), $where, 'sources must not be empty');
    for my $s (@{ $data->{sources} }) {
        my ($suffix) = $s =~ /(\.[^.\/]*)$/;
        need($SOURCE_SUFFIX{ $suffix // '' }, $where, "unsupported source type: $s (use .c or .f)");
    }
    files_exist($path, $data->{sources}, $where, 'source');
    files_exist($path, $data->{headers} // [], $where, 'header');
    for my $lib (@{ $data->{extra_libs} // [] }) {
        need(scalar($lib =~ /^-[lL]/), $where, "extra_libs entries must be -l/-L flags: $lib");
    }
    my $lic = $data->{license};
    need(ref $lic eq 'HASH' && is_string($lic->{spdx}) && length $lic->{spdx}, $where, 'license.spdx is required');
    need(is_bool($lic->{redistributable}), $where, 'license.redistributable must be true or false');
    need(is_list_of_strings($lic->{files}) && scalar(@{ $lic->{files} }), $where, 'license.files must list at least one licence/notice file');
    files_exist($path, $lic->{files}, $where, 'licence');
    need(is_string($data->{metadata}) && -f "$path/$data->{metadata}", $where, "metadata file not found: $data->{metadata}");
    if ($data->{tests}) {
        need(-f "$path/$data->{tests}", $where, "tests script not found: $data->{tests}");
    }
    if ($data->{makefile}) {
        need(-f "$path/$data->{makefile}", $where, "makefile not found: $data->{makefile}");
    }

    my $mpath = "$path/$data->{metadata}";
    my $meta  = parse_json(slurp($mpath), $mpath);
    fail("$mpath: must be an object with a 'functions' object")
        unless ref $meta eq 'HASH' && ref $meta->{functions} eq 'HASH';
    my %have = %{ $meta->{functions} };
    my %want = map { $_ => 1 } @{ $data->{provides} };
    my @missing = sort grep { !exists $have{$_} } keys %want;
    my @extra   = sort grep { !exists $want{$_} } keys %have;
    if (@missing || @extra) {
        fail("$where: 'provides' and $data->{metadata} disagree"
            . (@missing ? "; not in metadata: [" . join(', ', map {"'$_'"} @missing) . "]" : '')
            . (@extra   ? "; not in provides: [" . join(', ', map {"'$_'"} @extra) . "]"   : ''));
    }
    return {
        path      => $path,
        data      => $data,
        name      => $name,
        provides  => $data->{provides},
        conflicts => $data->{conflicts} // [],
        sources   => $data->{sources},
        headers   => $data->{headers} // [],
        extra_libs => $data->{extra_libs} // [],
        metadata  => $data->{metadata},
        tests     => $data->{tests},
        makefile  => $data->{makefile},
        license   => $lic,
        requires_base => $data->{requires_base},
        functions => $meta->{functions},
        metadata_text => slurp($mpath),
    };
}

sub files_exist {
    my ($base, $names, $where, $what) = @_;
    for my $n (@$names) {
        need(-f "$base/$n", $where, "$what file not found: $n");
    }
}

sub base_version {
    my ($c_root) = @_;
    for my $rel (qw(core/onefit-3.1/makefile local/makefile)) {
        my $p = "$c_root/$rel";
        next unless -f $p;
        return $1 if slurp($p) =~ /^LIBNUMBER\s*=\s*([0-9][0-9.]*)/m;
    }
    return undef;
}

sub ver_cmp {
    my @a = split /\./, $_[0];
    my @b = split /\./, $_[1];
    while (@a || @b) {
        my ($x, $y) = (shift(@a) // 0, shift(@b) // 0);
        return $x <=> $y if $x != $y;
    }
    return 0;
}

sub check_requires_base {
    my ($ext, $c_root) = @_;
    return unless $ext->{requires_base};
    my ($op, $want) = $ext->{requires_base} =~ /^\s*(>=|<=|==|>|<)\s*([0-9][0-9.]*)\s*$/
        or fail("$ext->{name}: requires_base must look like '>=4.0.4'");
    my $have = base_version($c_root) // return;
    my $c = ver_cmp($have, $want);
    my %ok = ('>=' => $c >= 0, '<=' => $c <= 0, '==' => $c == 0, '>' => $c > 0, '<' => $c < 0);
    fail("$ext->{name} requires base $ext->{requires_base}, this base is $have") unless $ok{$op};
}

sub discover {
    my ($ext_dir, $include_template) = @_;
    my (@exts, @legacy);
    return (\@exts, \@legacy) unless -d $ext_dir;
    opendir my $dh, $ext_dir or fail("cannot read $ext_dir: $!");
    my @names = sort grep { !/^\./ } readdir $dh;
    closedir $dh;
    for my $n (@names) {
        my $d = "$ext_dir/$n";
        next unless -d $d;
        next if $SKIP_DIRS{$n} && !$include_template;
        if (-f "$d/extension.json") {
            push @exts, load_extension($d, $include_template);
        } elsif (-f "$d/Makefile") {
            push @legacy, $d;
        }
    }
    return (\@exts, \@legacy);
}

sub base_functions {
    my ($c_root) = @_;
    my $p = "$c_root/META-C.json";
    return ({}, '') unless -f $p;
    my $text = slurp($p);
    my $data = parse_json($text, $p);
    fail("$p: metadata root must be an object") unless ref $data eq 'HASH';
    return ($data, $text);
}

sub check_set {
    my ($exts, $base) = @_;
    my %names = map { $_->{name} => $_ } @$exts;
    for my $e (@$exts) {
        for my $c (@{ $e->{conflicts} }) {
            next unless $names{$c};
            fail("extension '$e->{name}' conflicts with '$c' - install only one of them "
                . "(remove extensions/$c or extensions/$e->{name})");
        }
    }
    my %owner;
    for my $e (@$exts) {
        for my $fn (@{ $e->{provides} }) {
            fail("function '$fn' is provided by both '$owner{$fn}' and '$e->{name}'") if $owner{$fn};
            fail("extension '$e->{name}' redefines '$fn', which the base catalog already has") if exists $base->{$fn};
            $owner{$fn} = $e->{name};
        }
    }
}

sub run_or_fail {
    my ($what, @cmd) = @_;
    system(@cmd) == 0 or fail("$what failed: " . join(' ', @cmd));
}

sub build_extension {
    my ($ext, $c_root, $root) = @_;
    my @cmd;
    if ($ext->{makefile}) {
        # Explicit opt-in only: a leftover Makefile from an older layout (it
        # installs to other paths and edits META-C.json) must never be picked
        # up just because it exists.
        @cmd = ('make', '-C', $ext->{path}, '-f', $ext->{makefile}, 'install', "C_ROOT=$c_root", "ROOT=$root");
    } else {
        @cmd = ('make', '-f', "$c_root/extensions/extension.mk", '-C', $ext->{path},
            "EXT_NAME=$ext->{name}",
            'EXT_SOURCES=' . join(' ', @{ $ext->{sources} }),
            'EXT_HEADERS=' . join(' ', @{ $ext->{headers} }),
            'EXT_LICENSE_FILES=' . join(' ', @{ $ext->{license}{files} }),
            "EXT_METADATA=$ext->{metadata}",
            "C_ROOT=$c_root", "ROOT=$root", 'install');
    }
    print STDERR "===> building extension $ext->{name} $ext->{data}{version}\n";
    run_or_fail('build step', @cmd);
}

sub run_tests {
    my ($ext, $c_root, $root) = @_;
    return unless $ext->{tests};
    print STDERR "===> testing extension $ext->{name}\n";
    local $ENV{C_ROOT}   = $c_root;
    local $ENV{ROOT}     = $root;
    local $ENV{EXT_NAME} = $ext->{name};
    my $script = abs_path("$ext->{path}/$ext->{tests}");
    # Through its own shebang (bash-only scripts exist); plain sh only for a
    # script that isn't marked executable.
    my @cmd = -x $script ? ($script) : ('sh', $script);
    my $cwd = getcwd();
    chdir $ext->{path} or fail("cannot enter $ext->{path}: $!");
    my $rc = system(@cmd);
    chdir $cwd;
    fail("tests failed for extension $ext->{name}") unless $rc == 0;
}

sub write_extensions_mk {
    my ($root, $exts) = @_;
    my (@libs, @incs);
    for my $e (@$exts) {
        push @libs, "-lonefit-ext-$e->{name}";
        push @incs, "-I$root/include/ext/$e->{name}";
    }
    for my $e (@$exts) {
        for my $l (@{ $e->{extra_libs} }) {
            push @libs, $l unless grep { $_ eq $l } @libs;
        }
    }
    make_path("$root/etc");
    spew("$root/etc/extensions.mk",
        "# Generated by onefite-c-code tools/extensions.pl - do not edit.\n"
        . "EXTERNAL_MODEL_LIBS := " . join(' ', @libs) . "\n"
        . "EXTERNAL_MODEL_INCLUDES := " . join(' ', @incs) . "\n");
}

sub write_catalog {
    my ($c_root, $exts, $base, $base_text) = @_;
    %RANK = ();
    note_key_order($base_text);
    note_key_order($_->{metadata_text}) for @$exts;
    my %merged = %$base;
    for my $e (@$exts) {
        $merged{$_} = $e->{functions}{$_} for keys %{ $e->{functions} };
    }
    spew("$c_root/META-CATALOG.json", encode_catalog(\%merged));
}

sub cmd_list {
    my ($o) = @_;
    my ($exts, $legacy) = discover("$o->{c_root}/extensions", $o->{include_template});
    for my $e (@$exts) {
        my $tag = $e->{license}{redistributable} ? 'redistributable' : 'NOT redistributable';
        print "$e->{name} $e->{data}{version}  [$e->{license}{spdx}, $tag]  provides: "
            . join(', ', @{ $e->{provides} }) . "\n";
    }
    for my $d (@$legacy) {
        (my $n = $d) =~ s{.*/}{};
        print "$n  (legacy bundle: no extension.json, installed by doctor's older path)\n";
    }
    print "(no extensions installed)\n" unless @$exts || @$legacy;
}

sub cmd_validate {
    my ($o) = @_;
    my $ext = load_extension($o->{path}, 1);
    check_requires_base($ext, $o->{c_root});
    my ($base) = base_functions($o->{c_root});
    check_set([$ext], $base);
    print "ok: $ext->{name} $ext->{data}{version} provides " . join(', ', @{ $ext->{provides} }) . "\n";
}

sub cmd_install {
    my ($o) = @_;
    my $c_root = abs_path($o->{c_root}) // fail("no such directory: $o->{c_root}");
    my $root = File::Spec->rel2abs($o->{root});   # not created until validation has passed
    my ($exts, $legacy) = discover("$c_root/extensions", $o->{include_template});
    my ($base, $base_text) = base_functions($c_root);
    check_requires_base($_, $c_root) for @$exts;
    check_set($exts, $base);
    for my $d (@$legacy) {
        (my $n = $d) =~ s{.*/}{};
        print STDERR "===> skipping legacy bundle $n (no extension.json)\n";
    }
    for my $e (@$exts) {
        unless ($e->{license}{redistributable}) {
            print STDERR "===> NOTE: '$e->{name}' is not redistributable ($e->{license}{spdx}); see "
                . "$e->{path}/$e->{license}{files}[0]\n";
        }
        build_extension($e, $c_root, $root);
        run_tests($e, $c_root, $root) if $o->{test};
    }
    write_extensions_mk($root, $exts);
    write_catalog($c_root, $exts, $base, $base_text);
    print STDERR "===> " . scalar(@$exts) . " extension(s) installed into $root\n";
}

sub main {
    my @argv = @_;
    my $cmd = shift @argv // '';
    my %o = (c_root => abs_path(dirname(abs_path($0)) . '/..'));
    my $ok = GetOptionsFromArray(\@argv,
        'c-root=s' => \$o{c_root}, 'root=s' => \$o{root},
        'test' => \$o{test}, 'include-template' => \$o{include_template});
    fail('bad options') unless $ok;
    if ($cmd eq 'list') {
        cmd_list(\%o);
    } elsif ($cmd eq 'validate') {
        $o{path} = shift @argv // fail('validate needs a PATH');
        cmd_validate(\%o);
    } elsif ($cmd eq 'install') {
        fail('install needs --root DIR') unless defined $o{root};
        cmd_install(\%o);
    } else {
        print STDERR "usage: extensions.pl {list|validate PATH|install --root DIR} [--c-root DIR] [--test] [--include-template]\n";
        return 2;
    }
    return 0;
}

my $rc = eval { main(@ARGV) };
if (!defined $rc) {
    print STDERR $@;
    exit 1;
}
exit $rc;
