package MARC::Field;

use 5.6.0;
use strict;
use warnings;
use integer;

use constant SUBFIELD_INDICATOR => "\x1F";
use constant END_OF_FIELD       => "\x1E";

our $ERROR = undef;

=pod

=head1 NAME

MARC::Field - Perl extension for handling MARC fields

=head1 SYNOPSIS

  use MARC::Field;

  my $field = 
  	MARC::Field->new( 
		245, '1', '0',
			'a' => 'Raccoons and ripe corn / ',
			'c' => 'Jim Arnosky.'
		);
  $field->add_subfields( "a", "1st ed." );

=head1 DESCRIPTION

Defines MARC fields for use in the MARC::Record module.  I suppose
you could use them on their own, but that wouldn't be very interesting.

=head1 EXPORT

None by default.  Any errors are stored in C<$MARC::Field::ERROR>, which
C<$MARC::Record> usually bubbles up to C<$MARC::Record::ERROR>.

=head1 METHODS

=head2 new(tag,indicator1,indicator2,code,data[,code,data...])

  my $record = 
  	MARC::Field->new( 
		245, '1', '0',
			'a' => 'Raccoons and ripe corn / ',
			'c' => 'Jim Arnosky.'
		);

=cut

sub new($) {
	my $class = shift;
	$class = ref($class) || $class;

	my $tagno = shift;
	($tagno =~ /^\d\d\d$/)
		or return _gripe( "Tag \"$tagno\" is not a valid tag number." );

	my $self = bless { _tag => $tagno }, $class;
	
	if ( $tagno < 10 ) { 
		$self->{_data} = shift;
	} else {
		for my $indcode ( qw( _ind1 _ind2 ) ) {
			my $indicator = shift;
			if ( $indicator !~ /^[0-9 ]$/ ) {
				$indicator = " ";
				warn "Invalid indicator \"$indicator\" forced to blank" unless ($indicator eq "");
			}
			$self->{$indcode} = $indicator;
		} # for
		
		(@_ >= 2)
			or return _gripe( "Must pass at least one subfield" );

		# Normally, we go thru add_subfields(), but internally we can cheat
		$self->{_subfields} = [@_];
	}

	return $self;
} # new()

=head2 tag()

Returns the three digit tag for the field.

=cut

sub tag {
	my $self = shift;
	return $self->{_tag};
}

=head2 indicator(indno)

Returns the specified indicator.  Returns C<undef> and sets 
C<$MARC::Field::ERROR> if the I<indno> is not 1 or 2, or if 
the tag doesn't have indicators.

=cut

sub indicator($) {
	my $self = shift;
	my $indno = shift;

	($self->tag >= 10)
		or return _gripe( "Fields below 010 do not have indicators" );

	if ( $indno == 1 ) {
		return $self->{_ind1};
	} elsif ( $indno == 2 ) {
		return $self->{_ind2};
	} else {
		return _gripe( "Indicator number must be 1 or 2" );
	}
}



=head2 subfield(code)

Returns the text from the first subfield matching the subfield code.
If no matching subfields are found, C<undef> is returned.

If the tag is less than an 010, C<undef> is returned and
C<$MARC::Field::ERROR> is set.

=cut

sub subfield {
	my $self = shift;
	my $code_wanted = shift;

	($self->tag >= 10)
		or return _gripe( "Fields below 010 do not have subfields" );

	my @data = @{$self->{_subfields}};
	while ( defined( my $code = shift @data ) ) {
		return shift @data if ( $code eq $code_wanted );
		shift @data;
	}

	return undef;
}

sub _gripe(@) {
	$ERROR = join( "", @_ );

	return undef;
}

=head2 data

Returns the data part of the field, if the tag number is less than 10.

=cut

sub data($) {
	my $self = shift;

	($self->{_tag} < 10)
		or return _gripe( "data() is only for tags less than 10" );
		
	my $data = shift;
	$self->{_data} = $data if defined( $data );

	return $self->{_data};
}

=head2 add_subfields(code,text[,code,text ...])

Adds subfields to the end of the subfield list.

Returns the number of subfields added, or C<undef> if there was an error.

=cut

sub add_subfields(@) {
	my $self = shift;

	($self->{_tag} >= 10)
		or return _gripe( "Subfields are only for tags >= 10" );

	push( @{$self->{_subfields}}, @_ );
	return @_/2;
}


=head2 as_string()

Returns a pretty string for printing in a MARC dump.

=cut

sub as_string() {
	my $self = shift;

	my @lines;

	if ( $self->tag < 10 ) {
		push( @lines, sprintf( "%03d     %s", $self->{_tag}, $self->{_data} ) );
	} else {
		my $hanger = sprintf( "%03d %1.1s%1.1s", $self->{_tag}, $self->{_ind1}, $self->{_ind2} );

		my @subdata = @{$self->{_subfields}};
		while ( @subdata ) {
			my $code = shift @subdata;
			my $text = shift @subdata;
			push( @lines, sprintf( "%-6.6s _%1.1s%s", $hanger, $code, $text ) );
			$hanger = "";
		} # for
	}



	return join( "\n", @lines );
}


=head2 as_usmarc()

Returns a string for putting into a USMARC file.  It's really only
useful by C<MARC::Record::as_usmarc()>.

=cut

sub as_usmarc() {
	my $self = shift;

	# Tags < 010 are pretty easy
	if ( $self->tag < 10 ) {
		return $self->data . END_OF_FIELD;
	} else {
		my @subs;
		my @subdata = @{$self->{_subfields}};
		while ( @subdata ) {
			push( @subs, join( "", SUBFIELD_INDICATOR, shift @subdata, shift @subdata ) );
		} # while

		return join( "", 
			$self->indicator(1),
			$self->indicator(2),
			@subs,
			END_OF_FIELD,
			);
	}
}

1;

__END__

=head1 AUTHOR

Andy Lester, E<lt>andy@petdance.comE<gt> or E<lt>alester@flr.follett.comE<gt>

=head1 SEE ALSO

See the "SEE ALSO" section for L<MARC::Record>.

=head1 TODO

=item * 

None

=cut
