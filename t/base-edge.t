#!/usr/bin/env perl

# Edge case tests for Digest::base:
# - reset() behavior
# - Method chaining from add()
# - Multiple sequential digests (auto-reset)
# - addfile() error handling
# - b64digest argument forwarding consistency
# - base64_padded_digest padding correctness
# - add_bits with exact byte boundaries

use strict;
use warnings;

use Test::More tests => 15;

use File::Temp 'tempfile';

# A mock digest that tracks state and supports arguments to digest()
{
    package TrackDigest;
    require Digest::base;
    our @ISA = qw(Digest::base);

    sub new {
        my $class = shift;
        if ( ref $class ) {
            # Instance method: reset in-place (as per Digest API contract)
            $class->{buf} = "";
            return $class;
        }
        bless { buf => "" }, $class;
    }

    sub add {
        my $self = shift;
        $self->{buf} .= join( "", @_ );
        return $self;
    }

    sub clone {
        my $self = shift;
        bless { buf => $self->{buf} }, ref($self);
    }

    sub digest {
        my $self = shift;
        my $buf  = $self->{buf};
        $self->{buf} = "";
        return $buf;
    }
}

# A mock that supports optional digest arguments (to test @_ forwarding)
{
    package ArgDigest;
    require Digest::base;
    our @ISA = qw(Digest::base);

    sub new {
        my $class = shift;
        if ( ref $class ) {
            $class->{buf} = "";
            return $class;
        }
        bless { buf => "" }, $class;
    }

    sub add {
        my $self = shift;
        $self->{buf} .= join( "", @_ );
        return $self;
    }

    sub clone {
        my $self = shift;
        bless { buf => $self->{buf} }, ref($self);
    }

    # digest() returns buf, but if passed "marker" arg, prepends it
    sub digest {
        my $self   = shift;
        my $marker = shift || "";
        my $buf    = $self->{buf};
        $self->{buf} = "";
        return $marker . $buf;
    }
}

# --- Test 1: reset() returns to clean state ---
{
    my $ctx = TrackDigest->new;
    $ctx->add("data");
    $ctx->reset;
    is( $ctx->digest, "", "reset() clears accumulated data" );
}

# --- Test 2: Method chaining from add() ---
{
    my $ctx = TrackDigest->new;
    my $ret = $ctx->add("hello");
    is( $ret, $ctx, "add() returns \$self for chaining" );
}

# --- Test 3: Chained add produces same result as multi-arg add ---
{
    my $ctx1 = TrackDigest->new;
    $ctx1->add("ab")->add("cd");

    my $ctx2 = TrackDigest->new;
    $ctx2->add( "ab", "cd" );

    is( $ctx1->digest, $ctx2->digest,
        "Chained add() equivalent to multi-arg add()" );
}

# --- Test 4: Auto-reset after digest ---
{
    my $ctx = TrackDigest->new;
    $ctx->add("first");
    my $d1 = $ctx->digest;

    # After digest, state should be empty
    my $d2 = $ctx->digest;
    is( $d2, "", "digest resets state — second call returns empty" );
}

# --- Test 5: Auto-reset after digest allows new accumulation ---
{
    my $ctx = TrackDigest->new;
    $ctx->add("first");
    $ctx->digest;    # consume and reset

    $ctx->add("second");
    is( $ctx->digest, "second",
        "After digest reset, new data accumulates fresh" );
}

# --- Test 6: hexdigest also resets state ---
{
    my $ctx = TrackDigest->new;
    $ctx->add("xyz");
    $ctx->hexdigest;    # consume
    is( $ctx->digest, "", "hexdigest resets state like digest" );
}

# --- Test 7: b64digest also resets state ---
{
    my $ctx = TrackDigest->new;
    $ctx->add("xyz");
    $ctx->b64digest;    # consume
    is( $ctx->digest, "", "b64digest resets state like digest" );
}

# --- Test 8: clone preserves state independently ---
{
    my $ctx = TrackDigest->new;
    $ctx->add("shared");
    my $clone = $ctx->clone;

    $ctx->add("_original");
    $clone->add("_clone");

    is( $ctx->digest,   "shared_original", "Original diverges after clone" );
    is( $clone->digest, "shared_clone",    "Clone diverges independently" );
}

# --- Test 9: base64_padded_digest includes padding ---
{
    my $ctx = TrackDigest->new;
    $ctx->add("abc");    # 3 bytes -> 4 base64 chars -> needs 0 padding (multiple of 4)
    my $padded = $ctx->base64_padded_digest;
    # "abc" base64 = "YWJj" (no padding needed for 3 bytes)
    is( $padded, "YWJj", "base64_padded_digest encodes correctly" );
}

# --- Test 10: b64digest strips padding ---
{
    my $ctx = TrackDigest->new;
    $ctx->add("a");    # 1 byte -> base64 "YQ==" -> stripped to "YQ"
    my $b64 = $ctx->b64digest;
    is( $b64, "YQ", "b64digest strips trailing = padding" );
}

# --- Test 11: b64digest forwards @_ to base64_padded_digest -> digest ---
{
    my $ctx = ArgDigest->new;
    $ctx->add("data");
    my $hex_with_marker = $ctx->hexdigest("M");
    # hexdigest("M") calls digest("M") which returns "M" . "data" = "Mdata"
    # then hex-encodes it

    my $ctx2 = ArgDigest->new;
    $ctx2->add("data");
    my $b64_with_marker = $ctx2->b64digest("M");
    # b64digest("M") should forward to base64_padded_digest("M") -> digest("M")
    # which returns "Mdata", then base64-encoded with padding stripped

    require MIME::Base64;
    my $expected_hex = unpack( "H*", "Mdata" );
    my $expected_b64 = MIME::Base64::encode( "Mdata", "" );
    $expected_b64 =~ s/=+$//;

    is( $hex_with_marker, $expected_hex,
        "hexdigest forwards args to digest" );
    is( $b64_with_marker, $expected_b64,
        "b64digest forwards args through to digest" );
}

# --- Test 12: addfile reads entire file content ---
{
    my ( $fh, $tempfile ) = tempfile( UNLINK => 1 );
    binmode($fh);
    print $fh "file_content";
    close($fh) || die;

    my $ctx = TrackDigest->new;
    open( my $rfh, "<", $tempfile ) || die;
    binmode($rfh);
    $ctx->addfile($rfh);
    close($rfh);

    is( $ctx->digest, "file_content", "addfile reads complete file" );
}

# --- Test 13: addfile croaks on read error ---
{
    # Create a filehandle that will fail on read by closing it first
    my ( $fh, $tempfile ) = tempfile( UNLINK => 1 );
    close($fh);

    my $ctx = TrackDigest->new;
    open( my $rfh, "<", $tempfile ) || die;
    close($rfh);    # close it so read() will fail

    eval { $ctx->addfile($rfh) };
    like( $@, qr/Read failed/, "addfile croaks on read error" );
}
