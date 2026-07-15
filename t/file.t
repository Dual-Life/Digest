#!perl -w

use strict;
use warnings;

use Test::More tests => 9;

use File::Temp 'tempfile';

{

    package Digest::Foo;
    $INC{'Digest/Foo.pm'} = "local";
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
        my $self = shift;
        return sprintf "%04d", length($$self);
    }
}

use Digest::file qw(digest_file_ctx digest_file digest_file_hex digest_file_base64);

{
    my ( $fh, $file ) = tempfile( UNLINK => 1 );
    binmode($fh);
    print $fh "foo\0\n";
    close($fh) || die "Can't write '$file': $!";

    is( digest_file( $file, "Foo" ), "0005" );

    if ( ord('A') == 193 ) {    # EBCDIC.
        is( digest_file_hex( $file, "Foo" ), "f0f0f0f5" );
        is( digest_file_base64( $file, "Foo" ), "8PDw9Q" );
    }
    else {
        is( digest_file_hex( $file, "Foo" ), "30303035" );
        is( digest_file_base64( $file, "Foo" ), "MDAwNQ" );
    }
}

# digest_file_ctx returns a usable Digest context object
{
    my ( $fh2, $file2 ) = tempfile( UNLINK => 1 );
    binmode($fh2);
    print $fh2 "test data";
    close($fh2) || die "Can't write '$file2': $!";

    my $ctx = digest_file_ctx( $file2, "Foo" );
    isa_ok( $ctx, "Digest::Foo", "digest_file_ctx returns correct class" );
    is( $ctx->digest, "0009", "digest_file_ctx feeds file content to context" );
}

# Error handling
ok !eval { digest_file_ctx( "not-there.txt", "Foo" ) };
like $@, qr/Can't open/, "digest_file_ctx croaks on missing file";

ok !eval { digest_file( "not-there.txt", "Foo" ) };
ok $@;
