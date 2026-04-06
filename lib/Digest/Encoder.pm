package Digest::Encoder;

use strict;
use warnings;

our $VERSION = "1.20";

use Encode ();

sub _wrap {
    my ($class, $ctx, $encoding) = @_;
    bless {
        _ctx      => $ctx,
        _encoding => $encoding,
    }, $class;
}

sub add {
    my $self = shift;
    $self->{_ctx}->add(map { Encode::encode($self->{_encoding}, $_) } @_);
    return $self;
}

# Methods that return $self for chaining need to return the wrapper
sub addfile {
    my $self = shift;
    $self->{_ctx}->addfile(@_);
    return $self;
}

sub add_bits {
    my $self = shift;
    $self->{_ctx}->add_bits(@_);
    return $self;
}

sub reset {
    my $self = shift;
    $self->{_ctx}->reset(@_);
    return $self;
}

# Delegate all other methods to the underlying context
our $AUTOLOAD;

sub AUTOLOAD {
    my $self = shift;
    my $method = substr($AUTOLOAD, rindex($AUTOLOAD, '::') + 2);
    return if $method eq 'DESTROY';
    $self->{_ctx}->$method(@_);
}

sub can {
    my ($self, $method) = @_;
    my $code = $self->SUPER::can($method);
    return $code if $code;
    return $self->{_ctx}->can($method);
}

sub isa {
    my ($self, $class) = @_;
    return 1 if $self->SUPER::isa($class);
    return $self->{_ctx}->isa($class);
}

1;

__END__

=head1 NAME

Digest::Encoder - Encoding wrapper for Digest objects

=head1 DESCRIPTION

This is an internal wrapper class used by L<Digest> when the C<encoding>
option is passed to C<< Digest->new() >>. It intercepts C<add()> calls
and encodes strings using L<Encode> before passing them to the underlying
digest implementation.

You should not need to use this class directly. Instead, use:

  my $ctx = Digest->new("SHA-256", encoding => "UTF-8");
  $ctx->add($unicode_string);  # automatically encoded

=head1 SEE ALSO

L<Digest>, L<Encode>

=cut
