package MARC::Lint;

=head1 NAME

MARC::Lint - Perl extension for checking validity of MARC records

=cut

use 5.6.0;
use strict;
use warnings;
use integer;

use MARC::Record;
use MARC::Field;


=head1 SYNOPSIS

  use MARC::Record;
  use MARC::Lint;


  my $linter = new MARC::Lint;
  
  open( IN, "<", $filename ) or die "Couldn't open $filename: $!\n";
  binmode( IN ); # for the Windows folks
  while ( !eof(IN) ) {
  	my $marc = MARC::Record::next_from_file( *IN );
	die $MARC::Record::ERROR unless $marc;

	$linter->check_record( $marc );


	# Print the title tag
	print $marc->subfield(245,"a"), "\n";

	# Print the errors that were found
	print join( "\n", $linter->warnings ), "\n";
  } # while

  close IN or die "Error closing $filename: $!\n";

Given the following MARC record:

  100 14 _aWall, Larry.
  110 1  _aO'Reilly & Associates.
  245 90 _aProgramming Perl /
         _aBig Book of Perl /
         _cLarry Wall, Tom Christiansen & Jon Orwant.
  250    _a3rd ed.
  250    _a3rd ed.
  260    _aCambridge, Mass. :
         _bO'Reilly,
         _r2000.

the following errors are generated:

	1XX: Only one 1XX tag is allowed, but I found 2 of them.
	100: Indicator 2 must be blank
	245: Indicator 1 must be 0 or 1
	245: Subfield _a is not repeatable.
	250: Field is not repeatable.
	260: Subfield _r is not valid.
	260: Must have a subfield _c.

=head1 DESCRIPTION

Module for checking validity of MARC records.  99% of the users will want to do 
something like is shown in the synopsis.  The other intrepid 1% will overload the
C<MARC::Lint> module's methods and provide their own special field-level checking.

What this means is that if you have certain requirements, such as making sure that
all 952 tags have a certain call number in them, you can write a function that 
checks for that, and still get all the benefits of the MARC::Lint framework.

=head1 EXPORT

None.  Everything is done through objects.

=head1 METHODS

=head2 C<new()>

No parms needed.  The C<MARC::Lint> object is little more than a list of warnings 
and a bunch of rules.

=cut

sub new() {
	my $class = shift;
	$class = ref($class) || $class;

	my $self = {
		_warnings => [],
	};
	bless $self, $class;

	$self->_read_rules();

	return $self;
}

=head2 C<warnings()>

Returns a list of warnings found by C<check_record()> and its brethren.

=cut

sub warnings {
	my $self = shift;

	return @{$self->{_warnings}};
}

=head2 C<clear_warnings()>

Clear the list of warnings for this linter object.  It's automatically called
when you call C<check_record()>.

=cut

sub clear_warnings {
	my $self = shift;

	@{$self->{_warnings}} = [];
}

=head2 C<warn(str[,str...])>

Create a warning message, built from strings passed, like a C<print> statement.

Typically, you'll leave this to C<check_record()>, but industrious programmers
may want to do their own checking as well.

=cut

sub warn {
	my $self = shift;

	push( @{$self->{_warnings}}, join( "", @_ ) );

	return undef;
}

=head2 C<check_record(marc)>

Does all sorts of lint-like checks on the MARC record I<marc>, both on the record as a whole,
and on the individual fields & subfields.

=cut

sub check_record {
	my $self = shift;
	my $marc = shift;

	
	(ref($marc) eq "MARC::Record")
		or return $self->warn( "Must pass a MARC::Record object to check_record" );

	if ( (my @_1xx = $marc->field( "1XX" )) > 1 ) {
		$self->warn( "1XX: Only one 1XX tag is allowed, but I found ", scalar @_1xx, " of them." );
	}

	if ( not $marc->field( 245 ) ) {
		$self->warn( "245: No 245 tag." );
	}


	my %field_seen;
	my $rules = $self->{_rules};
	for my $field ( $marc->fields ) {
		my $tagno = $field->tag;
		my $tagrules = $rules->{$tagno} or next;

		if ( $tagrules->{NR} && $field_seen{$tagno} ) { 
			$self->warn( "$tagno: Field is not repeatable." );
		}

		if ( $tagno >= 10 ) {
			for my $ind ( 1..2 ) {
				if ( not ($field->indicator($ind) =~ $tagrules->{"ind$ind" . "_regex"}) ) {
					$self->warn( "$tagno: Indicator $ind must be ", $tagrules->{"ind$ind" . "_desc"} );
				}
			}
			
			my %sub_seen;
			for my $subfield ( $field->subfields ) {
				my ($code,$data) = @$subfield;

				my $rule = $tagrules->{$code};
				if ( not defined $rule ) {
					$self->warn( "$tagno: Subfield _$code is not valid." );
				} elsif ( ($rule eq "NR") && $sub_seen{$code} ) {
					$self->warn( "$tagno: Subfield _$code is not repeatable." );
				}

				++$sub_seen{$code};
			}
		}

		# Check to see if a check_xxx() function exists, and call it on the field if it does
		my $checker = "check_$tagno";
		if ( $self->can( $checker ) ) {
			$self->$checker( $field );
		}

		++$field_seen{$tagno};
	} # for

	return;
}

=head2 C<check_I<xxx>(field)>

Various functions to check the different fields.  If the function doesn't exist, 
then it doesn't get checked.

=cut

sub check_245 {
	my $self = shift;
	my $field = shift;

	if ( not $field->subfield( "a" ) ) {
		$self->warn( "245: Must have a subfield _a." );
	}
}

sub check_260 {
	my $self = shift;
	my $field = shift;

	if ( not $field->subfield( "c" ) ) {
		$self->warn( "260: Must have a subfield _c." );
	}
}


=head1 SEE ALSO

Check the docs for L<MARC::Record>.  All software links are there.

=head1 TODO

=over 4

=item * ISBN and ISSN checking

We can check the 020 and 022 fields with the C<Business::ISBN> and 
C<Business::ISSN> modules, respectively.

=back

=head1 LICENSE

This code may be distributed under the same terms as Perl itself. 

Please note that these modules are not products of or supported by the
employers of the various contributors to the code.

=head1 AUTHOR

Andy Lester, E<lt>marc@petdance.comE<gt> or E<lt>alester@flr.follett.comE<gt>

=cut

# Used only to read the stuff from __DATA__
sub _read_rules() {
	my $self = shift;
	
	my $tell = tell(DATA);  # Stash the position so we can reset it for next time

	local $/ = "";
	while ( my $lines = <DATA> ) {
		$lines =~ s/\s+$//;
		my @keyvals = split( /\s+/, $lines );

		my $tagno = shift @keyvals;
		my $repeatable = shift @keyvals;

		my $rules = ($self->{_rules}->{$tagno} ||= {});
		$rules->{$repeatable} = $repeatable;

		while ( @keyvals ) {
			my $key = shift @keyvals;
			my $val = shift @keyvals;
			
			$rules->{$key} = $val;

			# Do magic for indicators
			if ( $key =~ /^ind/ ) {
				my $desc;
				my $regex;
				
				if ( $val eq "blank" ) {
					$desc = "blank";
					$regex = qr/^ $/;
				} else {
					$desc = _nice_list($val);
					$regex = qr/^[$val]$/;
				}

			$rules->{$key."_desc"} = $desc;
			$rules->{$key."_regex"} = $regex;
			}
		}
	} # while
	seek( DATA, $tell, 0 );
}

sub _nice_list($) {
	my $str = shift;

	if ( $str =~ s/(\d)-(\d)/$1 thru $2/ ) {
		return $str;
	}

	my @digits = split( //, $str );
	my $last = pop @digits;
	return join( ", ", @digits ) . " or $last";
}

sub _ind_regex($) {
	my $str = shift;

	return qr/^ $/ if $str eq "blank";

	return qr/^[$str]$/;
}


1;

__DATA__
100	NR
ind1	013
ind2	blank
a	NR
q	NR
b	R
c	R
d	NR
e	R

110	NR
ind1	012
ind2	blank
a	NR
b	R

111	NR
ind1	012
ind2	blank
a	NR
n	R	
d	NR
c	NR
e	R

130	NR
ind1	0-9
ind2	blank
a	NR
n	R
p	R
h	NR
l	NR
k	R
s	NR
f	NR

240	NR
ind1	01
ind2	0-9

245	NR
ind1	01
ind2	0-9
a	NR
n	R
p	R
h	NR
b	NR
s	NR
c	NR

246	NR
ind1	0123
ind2	012345678
a	NR
h	NR
b	NR
n	R
p	R
i	NR
f	NR

250	NR
ind1	blank
ind2	blank
a	NR
b	NR

260	NR
ind1	blank
ind2	blank
a	R
b	R
c	R

300	NR
ind1	blank
ind2	blank
a	R
b	NR
c	R
e	NR

440	R
ind1	blank
ind2	0-9
a	NR
n	R
p	R
v	NR

490	R
ind1	01
ind2	blank
a	R
v	R

800	R
ind1	013
ind2	blank
a	NR
q	NR
b	NR
c	R
d	NR
t	NR
e	R
v	NR
