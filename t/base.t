#!perl -w

use strict;
use warnings;

use Test::More tests => 18;

use File::Temp 'tempfile';

{

    package LenDigest;
    require Digest::base;
    our @ISA = qw(Digest::base);

    sub new {
        my $class = shift;
        my $str   = "";
        bless \$str, $class;
    }

    sub add {
        my $self = shift;
        $$self .= join( "", @_ );
        return $self;
    }

    sub digest {
        my $self  = shift;
        my $len   = length($$self);
        my $first = ( $len > 0 ) ? substr( $$self, 0, 1 ) : "X";
        $$self = "";
        return sprintf "$first%04d", $len;
    }
}

my $ctx = LenDigest->new;
is( $ctx->digest, "X0000" );

my $EBCDIC = ord('A') == 193;

if ($EBCDIC) {
    is( $ctx->hexdigest,            "e7f0f0f0f0" );
    is( $ctx->b64digest,            "5/Dw8PA" );
    is( $ctx->base64_padded_digest, "5/Dw8PA=" );
}
else {
    is( $ctx->hexdigest,            "5830303030" );
    is( $ctx->b64digest,            "WDAwMDA" );
    is( $ctx->base64_padded_digest, "WDAwMDA=" );
}

$ctx->add("foo");
is( $ctx->digest, "f0003" );

$ctx->add("foo");
is( $ctx->hexdigest, $EBCDIC ? "86f0f0f0f3" : "6630303033" );

$ctx->add("foo");
is( $ctx->b64digest, $EBCDIC ? "hvDw8PM" : "ZjAwMDM" );

{
    my ( $fh, $tempfile ) = tempfile( UNLINK => 1 );
    binmode($fh);
    print $fh "abc" x 100, "\n";
    close($fh) || die;

    open( my $fh2, $tempfile ) || die;
    $ctx->addfile($fh2);
    close($fh2);

    is( $ctx->digest, "a0301" );
}

eval { $ctx->add_bits("1010"); };
like( $@, '/^Number of bits must be multiple of 8/' );

$ctx->add_bits( $EBCDIC ? "11100100" : "01010101" );
is( $ctx->digest, "U0001" );

eval { $ctx->add_bits( "abc", 12 ); };
like( $@, '/^Number of bits must be multiple of 8/' );

$ctx->add_bits( "abc", 16 );
is( $ctx->digest, "a0002" );

$ctx->add_bits( "abc", 32 );
is( $ctx->digest, "a0003" );

# b64url_digest - no +/ chars in this digest, so same as b64digest
$ctx->add("foo");
is( $ctx->b64url_digest, $EBCDIC ? "hvDw8PM" : "ZjAwMDM",
    "b64url_digest with no special chars" );

# b64url_digest with binary data containing + and /
{
    package BinDigest;
    require Digest::base;
    our @ISA = qw(Digest::base);

    sub new {
        my $class = shift;
        my $data = shift || "";
        bless \$data, $class;
    }

    sub add {
        my $self = shift;
        $$self .= join("", @_);
        return $self;
    }

    sub digest {
        my $self = shift;
        my $d = $$self;
        $$self = "";
        return $d;
    }
}

# \x03\xe0\x00 encodes to "A+AA" in standard base64
my $bin = BinDigest->new("\x03\xe0\x00");
is( $bin->b64digest,     "A+AA", "b64digest with + char" );
$bin = BinDigest->new("\x03\xe0\x00");
is( $bin->b64url_digest, "A-AA", "b64url_digest translates + to -" );

# \xff\xff\xfe encodes to "///+" in standard base64
$bin = BinDigest->new("\xff\xff\xfe");
is( $bin->b64digest,     "///+", "b64digest with / and + chars" );
$bin = BinDigest->new("\xff\xff\xfe");
is( $bin->b64url_digest, "___-", "b64url_digest translates / to _ and + to -" );
