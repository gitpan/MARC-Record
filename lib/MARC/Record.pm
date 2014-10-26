package MARC::Record;

=head1 NAME

MARC::Record - Perl extension for handling MARC records

=cut

use 5.004;
use strict;
use integer;
use vars qw( $VERSION $ERROR $DEBUG );

use MARC::Field;

=head1 VERSION

Version 0.10

=cut

$VERSION = '0.10';
$DEBUG = 0;

use constant SUBFIELD_INDICATOR	=> "\x1F";
use constant END_OF_FIELD	=> "\x1E";
use constant END_OF_RECORD	=> "\x1D";

use constant LEADER_LEN 		=> 24;
use constant DIRECTORY_ENTRY_LEN 	=> 12;


=head1 SYNOPSIS

  use MARC::Record;

  open( IN, "<", $filename ) or die "Couldn't open $filename: $!\n";
  binmode( IN ); # for the Windows folks
  while ( !eof(IN) ) {
  	my $marc = MARC::Record::next_from_file( *IN );
	die $MARC::Record::ERROR unless $marc;

	# Print the title tag
	print $marc->subfield(245,"a"), "\n";

	# Find any subject tags and print their _a subfields
	for my $subject ( $marc->field( "6XX" ) ) {
		print "\t", $subject->tag, ": ", $subject->subfield("a"), "\n";
	} # for subject
  } # while

  close IN or die "Error closing $filename: $!\n";

=head1 DESCRIPTION

Module for handling MARC records as objects, and reading them from USMARC files.

=head1 EXPORT

None.  

=head1 ERROR HANDLING

Any errors generated are stored in C<$MARC::Record::ERROR>. 
Warnings are kept with the record and accessible in the C<warnings()> method. 

=head1 METHODS

=head2 new()

Base constructor for the class. 

=cut

sub new($) {
	my $class = shift;
	$class = ref($class) || $class;

	my $self = {
		_leader => undef,
		_leader_refresh => 0,
		_fields => [],
		_warnings => [],
		};
	return bless $self, $class;
} # new()


=head2 new_from_usmarc()

Constructor for handling data from a USMARC file.  This function takes care of all
the directory parsing & mangling.

Any warnings or coercions can be checked in the C<warnings()> function.

=cut

sub new_from_usmarc($) {
	my $class = shift;
	my $text = shift;
	my $self = new($class);


	# Check for an all-numeric record length
	($text =~ /^(\d{5})/)
		or return _gripe( "Record length \"", substr( $text, 0, 5 ), "\" is not numeric" );

	my $reclen = $1;
	($reclen == length($text))
		or return _gripe( "Invalid record length: Leader says $reclen bytes, but it's actually ", length( $text ) );

	$self->leader( substr( $text, 0, LEADER_LEN ) );
	my @fields = split( END_OF_FIELD, substr( $text, LEADER_LEN ) );
	my $dir = shift @fields or return _gripe( "No directory found" );

	(length($dir) % 12 == 0)
		or return _gripe( "Invalid directory length" );
	my $nfields = length($dir)/12;

	my $finalfield = pop @fields;
	# Check for the record terminator, and ignore it
	($finalfield eq END_OF_RECORD)
		or $self->_warn( "Invalid record terminator: \"$finalfield\"" );

	# Walk thru the directories, and shift off the fields while we're at it
	# Shouldn't be any non-digits anywhere in any directory entry
	my @directory = unpack( "A3 A4 A5" x $nfields, $dir );
	my @bad = grep /\D/, @directory;
	if ( @bad ) { 
		return _gripe( "Non-numeric entries in the tag directory: ", join( ", ", map { "\"$_\"" } @bad ) );
	}

	my $databytesused = 0;
	while ( @directory ) {
		my $tagno = shift @directory;
		my $len = shift @directory;
		my $offset = shift @directory;
		my $tagdata = shift @fields;

		# Check directory validity
		($tagno =~ /^\d\d\d$/)
			or return _gripe( "Invalid field number in directory: \"$tagno\"" );

		($len == length($tagdata) + 1)
			or $self->_warn( "Invalid length in the directory for tag $tagno" );

		($offset == $databytesused)
			or $self->_warn( "Directory offsets are out of whack" );
		$databytesused += $len;

		if ( $tagno < 10 ) {
			$self->add_fields( $tagno, $tagdata )
				or return undef; # We're relying on add_fields() having set $MARC::Record::ERROR
		} else {
			my @subfields = split( SUBFIELD_INDICATOR, $tagdata );
			my $indicators = shift @subfields
				or return _gripe( "No subfields found." );
			my ($ind1,$ind2);
			if ( $indicators =~ /^([0-9 ])([0-9 ])$/ ) {
				($ind1,$ind2) = ($1,$2);
			} else {
				$self->_warn( "Invalid indicators \"$indicators\" forced to blanks\n" );
				($ind1,$ind2) = (" "," ");
			}
				
			# Split the subfield data into subfield name and data pairs
			my @subfield_data = map { (substr($_,0,1),substr($_,1)) } @subfields;
			$self->add_fields( $tagno, $ind1, $ind2, @subfield_data )
				or return undef;
		}
	} # while

	# Once we're done, there shouldn't be any fields left over: They should all have shifted off.
	(@fields == 0)
		or return _gripe( "I've got leftover fields that weren't in the directory" );

	return $self;
}

=head2 next_from_file(*FILEHANDLE)

Reads the next record from the file handle passed in.

  open( IN, "foo.marc" );
  while ( !eof(IN) ) {
	  my $marc = MARC::Record::next_from_file(*IN);
  } # while
  close IN;

=cut

sub next_from_file(*) {
	my $fh = shift;

	my $reclen;
	my $usmarc;

	read( $fh, $reclen, 5 )
		or return _gripe( "Error reading record length: $!" );

	$reclen =~ /^\d{5}$/
		or return _gripe( "Invalid record length \"$reclen\"" );
	$usmarc = $reclen;
	read( $fh, substr($usmarc,5), $reclen-5 )
		or return _gripe( "Error reading $reclen byte record: $!" );

	return MARC::Record->new_from_usmarc($usmarc);
}

=head2 leader([text])

Returns the leader for the record.  Sets the leader if I<text> is defined.
No error checking is done on the validity of the leader.

=cut

sub leader($) {
	my $self = shift;
	my $text = shift;

	if ( defined $text ) {
		(length($text) eq 24)
			or $self->_warn( "Leader must be 24 bytes long" );
=pod
		($text =~ /4500$/)
			$self->_warn( "Leader must end with 4500" );
=cut
		$self->{_leader} = $text;
	} # set the leader

	return $self->{_leader};
} # leader()

=head2 update_leader()

If any changes get made to the MARC record, the first 5 bytes of the
leader (the length) will be invalid.  This function updates the 
leader with the correct length of the record as it would be if
written out to a file.

=cut

sub update_leader() {
	my $self = shift;

	my (undef,undef,$reclen,$baseaddress) = $self->_build_tag_directory();

	$self->_set_leader_lengths( $reclen, $baseaddress );
}

=head2 _set_leader_lengths($$) 

Internal function for updating the leader's length and base address.

=cut

sub _set_leader_lengths($$) {
	my $self = shift;
	my $reclen = shift;
	my $baseaddr = shift;

	substr($self->{_leader},0,5)  = sprintf("%05d",$reclen);
	substr($self->{_leader},12,5) = sprintf("%05d",$baseaddr);
}

=head2 add_fields()

Adds MARC::Field objects to the end of the list.  Returns the number
of fields added, or C<undef> if there was an error.

There are three ways of calling C<add_fields()> to add data to the record.

=over 4

=item 1 Create a MARC::Field object and add it

  my $author = MARC::Field->new(
	        100, "1", " ", a => "Arnosky, Jim."
	        );
  $marc->add_fields( $author );

=item 2 Add the data fields directly, and let C<add_fields()> take care of the objectifying.

  $marc->add_fields(
        245, "1", "0",
                a => "Raccoons and ripe corn /",
                c => "Jim Arnosky.",
        	);

=item 3 Same as #2 above, but pass multiple fields of data in anonymous lists

  $marc->add_fields(
	[ 250, " ", " ", a => "1st ed." ],
	[ 650, "1", " ", a => "Raccoons." ],
	);

=back

=cut

sub add_fields(@) {
	my $self = shift;

	my $nfields = 0;
	my $fields = $self->{_fields};

	while ( my $parm = shift ) {
		# User handed us a list of data (most common possibility)
		if ( ref($parm) eq "" ) {
			my $field = MARC::Field->new( $parm, @_ )
				or return _gripe( $MARC::Field::ERROR );
			push( @$fields, $field );
			++$nfields;
			last; # Bail out, we're done eating parms

		# User handed us an object.
		} elsif ( ref($parm) eq "MARC::Field" ) {
			push( @$fields, $parm );
			++$nfields;

		# User handed us an anonymous list of parms
		} elsif ( ref($parm) eq "ARRAY" ) {
			my $field = MARC::Field->new(@$parm) 
				or return _gripe( $MARC::Field::ERROR );
			push( @$fields, $field );
			++$nfields;

		} else {
			return _gripe( "Unknown parm of type", ref($parm), " passed to add_fields()" );
		} # if

	} # while

	return $nfields;
}

=head2 delete_field(C<$field>)

Deletes a field from the record.

The field must have been retrieved from the record using the 
C<field()> method.  For example, to delete a 526 tag if it exists:

    my $tag526 = $marc->field( "526" );
    if ( $tag526 ) {
	$marc->delete_field( $tag526 );
    }

C<delete_field()> returns the number of fields that were deleted.
This shouldn't be 0 unless you didn't get the tag properly.

=cut

sub delete_field($) {
	my $self = shift;
	my $deleter = shift;
	my $list = $self->{_fields};

	my $old_count = @$list;
	@$list = grep { $_ != $deleter } @$list;
	return $old_count - @$list;
}


=head2 fields()

Returns a list of all the fields in the record.

=cut

sub fields() {
	my $self = shift;

	return @{$self->{_fields}};
}

=head2 field(tagspec)

Returns a list of tags that match the field specifier, or in scalar
context, just the first matching tag.

The field
specifier can be a simple number (i.e. "245"), or use the "X" notation
of wildcarding (i.e. subject tags are "6XX").

=cut

my %field_regex;

sub field($) {
	my $self = shift;
	my $tag = shift;

	my $regex = $field_regex{ $tag };

	# Compile & stash it if necessary
	if ( not defined $regex ) {
		my $pattern = $tag;
		$pattern =~ s/X/\\d/g;
		$regex = qr/^$pattern$/;
		$field_regex{ $tag } = $regex;
	} # not defined

	my @list = ();
	for my $maybe ( $self->fields ) {
		if ( $maybe->tag =~ $regex ) {
			return $maybe unless wantarray;

			push( @list, $maybe );
		} # if
	} # for

	return @list;
}

=head2 subfield(tag,subfield)

Shortcut method for getting just a subfield for a tag.  These are equivalent:

  my $title = $marc->field(245)->subfield("a");
  my $title = $marc->subfield(245,"a");

If either the field or subfield can't be found, C<undef> is returned.

=cut

sub subfield($$) {
	my $self = shift;
	my $tag = shift;
	my $subfield = shift;

	my $field = $self->field($tag) or return undef;
	return $field->subfield($subfield);
} # subfield()


=head2 as_formatted()

Returns a pretty string for printing in a MARC dump.

=cut

sub as_formatted() {
	my $self = shift;
		
	my @lines = ( "LDR " . ($self->{_leader} || "") );
	for my $field ( @{$self->{_fields}} ) {
		push( @lines, $field->as_formatted() );
	}

	return join( "\n", @lines );
} # as_formatted

=head2 title()

Returns the title from the 245 tag

=cut

sub title() {
	my $self = shift;

	my $field = $self->field(245) or return "<no 245 tag found>";

	return $field->as_string;
}

=head2 author()

Returns the author from the 100, 110 or 111 tag.

=cut

sub author() {
	my $self = shift;

	for my $tag ( qw( 100 110 111 ) ) {
		my $field = $self->field($tag);
		return $field->as_string() if $field;
	}

	return "<No author tag found>";
}


=head2 _build_tag_directory()

Function for internal use only: Builds the tag directory that gets
put in front of the data in a MARC record.

Returns two array references, and two lengths: The tag directory, and the data fields themselves,
the length of all data (including the Leader that we expect will be added),
and the size of the Leader and tag directory.

=cut

sub _build_tag_directory() {
	my $self = shift;

	my @fields;
	my @directory;

	my $dataend = 0;
	for my $field ( $self->fields() ) {
		# Dump data into proper format
		my $str = $field->as_usmarc;
		push( @fields, $str );

		# Create directory entry
		my $len = length $str;
		my $direntry = sprintf( "%03d%04d%05d", $field->tag, $len, $dataend );
		push( @directory, $direntry );
		$dataend += $len;
	}

	my $baseaddress = 
		LEADER_LEN +    # better be 24
		( @directory * DIRECTORY_ENTRY_LEN ) +
				# all the directory entries
		1;           	# end-of-field marker


	my $total = 
		$baseaddress +	# stuff before first field
		$dataend + 	# Length of the fields
		1;		# End-of-record marker



	return (\@fields, \@directory, $total, $baseaddress);
}

=head2 as_usmarc()

Returns a string of characters suitable for writing out to a USMARC file,
including the leader, directory and all the fields.

=cut

sub as_usmarc() {
	my $self = shift;

	my ($fields,$directory,$reclen,$baseaddress) = $self->_build_tag_directory();
	$self->_set_leader_lengths( $reclen, $baseaddress );

	# Glomp it all together
	return join("",$self->leader, @$directory, END_OF_FIELD, @$fields, END_OF_RECORD);
}


=head2 warnings()

Returns the warnings that were created when the record was read.
These are things like "Invalid indicators converted to blanks".

The warnings are items that you might be interested in, or might
not.  It depends on how stringently you're checking data.  If
you're doing some grunt data analysis, you probably don't care.

=cut

sub warnings() {
	my $self = shift;

	return @{$self->{_warnings}};
}

# NOTE: _warn is an object method
sub _warn($) {
	my $self = shift;

	push( @{$self->{_warnings}}, join( "", @_ ) );
}


# NOTE: _gripe is NOT an object method
sub _gripe(@) {
	$ERROR = join( "", @_ );

	return undef;
}


1;

__END__

=head1 DESIGN NOTES

A brief discussion of why MARC::Record is done the way it is:

=over 4

=item * It's built for quick prototyping

One of the areas Perl excels is in allowing the programmer to 
create easy solutions quickly.  C<MARC::Record> is designed along
those same lines.  You want a program to dump all the 6XX
tags in a file?  C<MARC::Record> is your friend.

=item * It's built for extensibility

Currently, I'm using C<MARC::Record> for analyzing bibliographic
data, but who knows what might happen in the future?  C<MARC::Record>
needs to be just as adept at authority data, too.

=item * It's designed around accessor methods

I use method calls everywhere, and I expect calling programs to do
the same, rather than accessing internal data directly.  If you
access an object's hash fields on your own, future releases may
break your code.

=item * It's not built for speed

One of the tradeoffs in using accessor methods is some overhead
in the method calls.  Is this slow?  I don't know, I haven't measured.
I would suggest that if you're a cycle junkie that you use
C<Benchmark.pm> to check to see where your bottlenecks are, and then
decide if C<MARC::Record> is for you.

=back

=head1 SEE ALSO

=over 4

=item * perl4lib (L<http://www.rice.edu/perl4lib/>)

A mailing list devoted to the use of Perl in libraries.


=item * Library Of Congress MARC pages (L<http://www.loc.gov/marc/>)

The definitive source for all things MARC.


=item * I<Understanding MARC Bibliographic> (L<http://lcweb.loc.gov/marc/umb/>)

Online version of the free booklet.  An excellent overview of the MARC format.  Essential.


=item * Tag Of The Month (L<http://www.tagofthemonth.com/>)

Follett Software Company's
(L<http://www.fsc.follett.com/>) monthly discussion of various MARC tags.

=back

=head1 TODO

=over 4

=item * Incorporate MARC.pm in the distribution.

Combine MARC.pm and MARC::* into one distribution.

=item * Podify MARC.pm

=item * Allow regexes across the entire tag

Imagine something like this:

  my @sears_headings = $marc->tag_grep( /Sears/ );

(from Mike O'Regan)

=item * Insert a field in an arbitrary place in the record

=item * Allow deleting a field

  for my $field ( $record->field( "856" ) ) {
	$record->delete_field( $field ) unless useful($field);
	} # for

(from Anne Highsmith hismith@tamu.edu)


=item * Modifying an existing field

=back

=head1 IDEAS

Ideas are things that have been considered, but nobody's actually asked for.

=over 4

=item * Read from MicroLIF

Create a C<new_from_microlif()> function that would handle the pretty 
MicroLIF format.  Basically, a reverse of C<as_microlif()>.

=item * Create multiple output formats.

These could be ASCII, XML, or MarcMaker.

=item * Create a clone of a record based on criteria

=back

=head1 LICENSE

This code may be distributed under the same terms as Perl itself. 

Please note that these modules are not products of or supported by the
employers of the various contributors to the code.

=head1 AUTHOR

Andy Lester, E<lt>marc@petdance.comE<gt> or E<lt>alester@flr.follett.comE<gt>

=cut

