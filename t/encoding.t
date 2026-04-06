#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Encode ();

# We need a digest implementation that records what bytes were added,
# so we can verify encoding behavior without depending on a specific
# digest algorithm's output.
{
    package Digest::Recorder;
    our @ISA = qw(Digest::base);
    require Digest::base;

    sub new {
        my $class = shift;
        bless { bytes => "" }, $class;
    }

    sub add {
        my $self = shift;
        $self->{bytes} .= join("", @_);
        return $self;
    }

    sub digest {
        my $self = shift;
        my $d = $self->{bytes};
        $self->{bytes} = "";
        return $d;
    }

    # Expose recorded bytes without resetting
    sub recorded_bytes { $_[0]->{bytes} }
}

# Set VERSION so Digest->new() sees the module as already loaded
$Digest::Recorder::VERSION = 1;

# Register our test implementation so Digest->new("Recorder") works
$Digest::MMAP{"Recorder"} = "Digest::Recorder";

use Digest;

# Test 1: Digest->new with encoding option returns a working context
{
    my $ctx = Digest->new("Recorder", encoding => "UTF-8");
    ok($ctx, "new() with encoding option returns a context");
    $ctx->add("hello");
    is($ctx->digest, "hello", "ASCII strings pass through unchanged");
}

# Test 2: encoding normalizes wide characters to specified encoding
{
    # Create a string with the UTF-8 flag on (wide character)
    my $latin1_bytes = "\xe4\xf8";  # ä and ø in Latin-1
    my $unicode_str = Encode::decode("latin1", $latin1_bytes);  # now a character string

    # Without encoding wrapper, manual encode gives us UTF-8 bytes
    my $expected_utf8 = Encode::encode("UTF-8", $unicode_str);

    my $ctx = Digest->new("Recorder", encoding => "UTF-8");
    $ctx->add($unicode_str);
    is($ctx->digest, $expected_utf8,
       "encoding option encodes character strings to specified encoding");
}

# Test 3: same characters produce same digest regardless of internal representation
{
    my $latin1_bytes = "\xe4\xf8";
    my $unicode_str = Encode::decode("latin1", $latin1_bytes);

    # Both should produce the same digest when encoding is specified
    my $ctx1 = Digest->new("Recorder", encoding => "UTF-8");
    $ctx1->add($unicode_str);
    my $d1 = $ctx1->digest;

    my $ctx2 = Digest->new("Recorder", encoding => "UTF-8");
    $ctx2->add($unicode_str);
    my $d2 = $ctx2->digest;

    is($d1, $d2, "same characters always produce the same digest");
}

# Test 4: different encodings produce different digests for non-ASCII
{
    my $latin1_bytes = "\xe4\xf8";
    my $unicode_str = Encode::decode("latin1", $latin1_bytes);

    my $ctx_utf8 = Digest->new("Recorder", encoding => "UTF-8");
    $ctx_utf8->add($unicode_str);
    my $d_utf8 = $ctx_utf8->digest;

    my $ctx_latin1 = Digest->new("Recorder", encoding => "latin1");
    $ctx_latin1->add($unicode_str);
    my $d_latin1 = $ctx_latin1->digest;

    isnt($d_utf8, $d_latin1,
         "different encodings produce different digests for non-ASCII chars");
}

# Test 5: method chaining works through the wrapper
{
    my $ctx = Digest->new("Recorder", encoding => "UTF-8");
    my $result = $ctx->add("foo")->add("bar");
    isa_ok($result, "Digest::Encoder", "add() returns wrapper for chaining");
    is($ctx->digest, "foobar", "chained add() calls accumulate correctly");
}

# Test 6: hexdigest and b64digest work through the wrapper
{
    my $ctx = Digest->new("Recorder", encoding => "UTF-8");
    $ctx->add("AB");
    is($ctx->hexdigest, "4142", "hexdigest works through wrapper");

    $ctx->add("AB");
    ok($ctx->b64digest, "b64digest works through wrapper");
}

# Test 7: isa reports correctly for the underlying implementation
{
    my $ctx = Digest->new("Recorder", encoding => "UTF-8");
    ok($ctx->isa("Digest::Recorder"), "isa reports underlying class");
    ok($ctx->isa("Digest::Encoder"), "isa reports wrapper class");
}

# Test 8: encoding option is extracted and not passed to implementation
{
    # Digest::Recorder->new() doesn't accept extra args,
    # so this would fail if encoding were passed through
    my $ctx = Digest->new("Recorder", encoding => "UTF-8");
    ok($ctx, "encoding option is consumed by Digest->new, not passed to impl");
}

# Test 9: without encoding option, behavior is unchanged
{
    my $ctx = Digest->new("Recorder");
    ok(!$ctx->isa("Digest::Encoder"), "no wrapper without encoding option");
    $ctx->add("hello");
    is($ctx->digest, "hello", "normal behavior without encoding option");
}

# Test 10: invalid encoding croaks
{
    eval { Digest->new("Recorder", encoding => "NoSuchEncoding999") };
    like($@, qr/encoding/i, "invalid encoding name croaks");
}

# Test 11: addfile works through the wrapper
{
    use File::Temp 'tempfile';
    my ($fh, $tempfile) = tempfile(UNLINK => 1);
    binmode($fh);
    print $fh "test data";
    close($fh);

    my $ctx = Digest->new("Recorder", encoding => "UTF-8");
    open(my $fh2, '<', $tempfile) or die;
    $ctx->addfile($fh2);
    close($fh2);

    is($ctx->digest, "test data", "addfile works through wrapper");
}

# Test 12: add with multiple arguments
{
    my $str = Encode::decode("latin1", "\xe4");
    my $ctx = Digest->new("Recorder", encoding => "UTF-8");
    $ctx->add("hello", $str, "world");
    my $expected = "hello" . Encode::encode("UTF-8", $str) . "world";
    is($ctx->digest, $expected, "add() with multiple args encodes each one");
}

done_testing;
