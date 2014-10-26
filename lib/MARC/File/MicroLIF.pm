package MARC::File::MicroLIF;

=head1 NAME

MARC::File::MicroLIF - MicroLIF-specific file handling

=cut

use 5.6.0;
use strict;
use integer;
use vars qw( $VERSION $ERROR );

=head1 VERSION

Version 0.91

    $Id: MicroLIF.pm,v 1.5 2002/04/02 14:08:39 petdance Exp $

=cut

our $VERSION = '0.91';

use MARC::File;
our @ISA = qw( MARC::File );

use MARC::Record qw( LEADER_LEN );

=head1 SYNOPSIS

    use MARC::File::MicroLIF;

    my $file = MARC::File::MicroLIF::in( $filename );
    
    while ( my $marc = $file->next() ) {
	# Do something
    }
    $file->close();
    undef $file;

=head1 EXPORT

None.  

=head1 METHODS

=cut

sub _next {
    my $self = shift;

    my $fh = $self->{fh};

    local $/ = "`\n";
    
    my $lifrec = <$fh>;

    return $lifrec;
}

sub decode {
    my $text = shift;
    $text = shift if (ref($text)||$text) =~ /^MARC::File/; # Handle being called as a method

    my $marc = MARC::Record->new();

    my @lines = split( /\n/, $text );
    for my $line ( @lines ) {
	# Ignore the file header if the calling program hasn't already dealt with it
	next if $line =~ /^HDR/;

	($line =~ s/^(\d\d\d|LDR)//) or
	return $marc->_gripe( "Invalid tag number: ", substr( $line, 0, 3 ) );
	my $tagno = $1;

	($line =~ s/\^$//) or $marc->_warn( "Tag $tagno is missing a trailing caret." );

	if ( $tagno eq "LDR" ) {
	    $marc->leader( substr( $line, 0, LEADER_LEN ) );
	} elsif ( $tagno < 10 ) {
	    $marc->add_fields( $tagno, $line );
	} else {
	    $line =~ s/^(.)(.)//;
	    my ($ind1,$ind2) = ($1,$2);
	    my @subfields;
	    my @subfield_data_pairs = split( /_(?=[a-z0-9])/, $line );
	    shift @subfield_data_pairs; # Leading _ makes an empty pair
	    for my $pair ( @subfield_data_pairs ) {
		my ($subfield,$data) = (substr( $pair, 0, 1 ), substr( $pair, 1 ));
		push( @subfields, $subfield, $data );
	    }
	    $marc->add_fields( $tagno, $ind1, $ind2, @subfields );
	}
    } # for

    return $marc;
}

1;

__END__

=head1 TODO

=over 4

=item * Squawks about the final field missing a caret

=back

=head1 RELATED MODULES

L<MARC::File>

=head1 LICENSE

This code may be distributed under the same terms as Perl itself. 

Please note that these modules are not products of or supported by the
employers of the various contributors to the code.

=head1 AUTHOR

Andy Lester, E<lt>marc@petdance.comE<gt> or E<lt>alester@flr.follett.comE<gt>

=cut

