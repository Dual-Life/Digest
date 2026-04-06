#!/usr/bin/env perl

# Test that Digest properly handles UTF-8 flagged strings.
# See https://github.com/Dual-Life/Digest/issues/2

use strict;
use warnings;

use Test::More;
use lib 't/lib';
use Digest;

# Create test strings with UTF-8 flag set
my $ascii_utf8 = "nonsense";
utf8::upgrade($ascii_utf8);

# U+00F6 = ö, encodes to 0xC3 0xB6 in UTF-8
my $latin1_utf8 = "bl\x{f6}dsinn";
utf8::upgrade($latin1_utf8);

# U+696D = 業, encodes to 0xE6 0xA5 0xAD in UTF-8
my $wide_utf8 = "\x{696d}";

# Verify our test strings have UTF-8 flag set
ok( utf8::is_utf8($ascii_utf8),  'setup: ascii string has UTF-8 flag' );
ok( utf8::is_utf8($latin1_utf8), 'setup: latin1 string has UTF-8 flag' );
ok( utf8::is_utf8($wide_utf8),   'setup: wide string has UTF-8 flag' );

# Test 1: ASCII string with UTF-8 flag - bytes are identical
{
    my $ctx = Digest->new("TestBytes");
    my $str = $ascii_utf8;
    $ctx->add($str);
    my $bytes = $ctx->digest;
    is( $bytes, "nonsense", 'ASCII UTF-8 string: correct bytes' );
    ok( utf8::is_utf8($str), 'ASCII UTF-8 string: flag preserved on original' );
}

# Test 2: Latin-1 string with UTF-8 flag
# "blödsinn" with UTF-8 flag should be encoded as UTF-8 bytes:
# bl + C3 B6 + dsinn = 9 bytes
{
    my $ctx = Digest->new("TestBytes");
    my $str = $latin1_utf8;
    $ctx->add($str);
    my $bytes = $ctx->digest;
    is( length($bytes), 9, 'Latin-1 UTF-8 string: 9 bytes (not 8)' );
    is( $bytes, "bl\xc3\xb6dsinn",
        'Latin-1 UTF-8 string: correct UTF-8 byte encoding' );
    ok( utf8::is_utf8($str),
        'Latin-1 UTF-8 string: flag preserved on original' );
}

# Test 3: Wide character string should not croak
# 業 (U+696D) encodes to 0xE6 0xA5 0xAD in UTF-8 (3 bytes)
{
    my $ctx = Digest->new("TestBytes");
    my $str = $wide_utf8;
    $ctx->add($str);
    my $bytes = $ctx->digest;
    is( length($bytes), 3, 'Wide char UTF-8 string: 3 bytes' );
    is( $bytes, "\xe6\xa5\xad",
        'Wide char UTF-8 string: correct UTF-8 byte encoding' );
    ok( utf8::is_utf8($str),
        'Wide char UTF-8 string: flag preserved on original' );
}

# Test 4: Non-UTF-8 byte string passes through unchanged
{
    my $ctx = Digest->new("TestBytes");
    my $str = "hello";
    ok( !utf8::is_utf8($str), 'byte string: no UTF-8 flag initially' );
    $ctx->add($str);
    my $bytes = $ctx->digest;
    is( $bytes, "hello", 'byte string: passed through unchanged' );
}

# Test 5: Multiple arguments, mixed UTF-8 and byte strings
{
    my $ctx      = Digest->new("TestBytes");
    my $utf8_str = "bl\x{f6}d";
    utf8::upgrade($utf8_str);
    my $byte_str = "sinn";
    $ctx->add( $utf8_str, $byte_str );
    my $bytes = $ctx->digest;
    is( $bytes, "bl\xc3\xb6dsinn", 'mixed args: correct bytes' );
    ok( utf8::is_utf8($utf8_str), 'mixed args: UTF-8 flag preserved' );
}

# Test 6: Method chaining still works
{
    my $ctx  = Digest->new("TestBytes");
    my $str1 = "bl\x{f6}d";
    utf8::upgrade($str1);
    my $str2   = "sinn";
    my $result = $ctx->add($str1)->add($str2);
    is( ref($result), ref($ctx), 'chaining: add returns self' );
    my $bytes = $ctx->digest;
    is( $bytes, "bl\xc3\xb6dsinn", 'chaining: correct bytes' );
}

done_testing;
