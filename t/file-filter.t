# $Id: file-filter.t,v 1.1 2003/01/29 18:14:35 petdance Exp $

use strict;
use integer;
eval 'use warnings' if $] >= 5.006;

use constant CAMEL_SKIPS => 8;

use Test::More tests=>(CAMEL_SKIPS * 2) + 7;

BEGIN {
    use_ok( 'MARC::File::USMARC' );
}

my $file = MARC::File::USMARC->in( 't/camel.usmarc' );
isa_ok( $file, 'MARC::File::USMARC', 'USMARC file' );

my $marc;
for ( 1..CAMEL_SKIPS ) { # Skip to the camel
    $marc = $file->next( sub { $_[0] == 245 } ); # Only want 245 in the record
    isa_ok( $marc, 'MARC::Record', 'Got a record' );

    is( scalar $marc->fields, 1, 'Should only have one tag' );
}

is( $marc->author,		'' );
is( $marc->title,		'Programming Perl / Larry Wall, Tom Christiansen & Jon Orwant.' );
is( $marc->title_proper,	'Programming Perl /' );
is( $marc->edition,		'' );
is( $marc->publication_date,	'' );

$file->close;

