
use strict;
use Test::More tests=>35;

BEGIN { use_ok( 'MARC::File::USMARC' ); }
BEGIN { use_ok( 'MARC::Lint' ); }


FROM_FILE: {
    my @expected = ( (undef) x 9, [ q{100: Indicator 1 must be 0, 1 or 3 but it's "2"} ] );

    my $lint = new MARC::Lint;
    isa_ok( $lint, 'MARC::Lint' );

    my $filename = "t/camel.usmarc";

    my $file = MARC::File::USMARC->in( $filename );
    while ( my $marc = $file->next() ) {
	isa_ok( $marc, 'MARC::Record' );
	my $title = $marc->title;
	$lint->check_record( $marc );

	my $expected = shift @expected;
	my @warnings = $lint->warnings;

	if ( $expected ) {
	    ok( eq_array( \@warnings, $expected ), "Warnings match on $title" );
	} else {
	    is( scalar @warnings, 0, "No warnings on $title" );
	}
    } # while

    is( scalar @expected, 0, "All expected messages have been exhausted." );
}


FROM_TEXT: {
    my $marc = MARC::Record->new();
    isa_ok( $marc, 'MARC::Record', 'MARC record' );

    $marc->leader("00000nam  22002538a 4500"); # The ????? represents meaningless digits at this point
    my $nfields = $marc->add_fields(
	[100, "1","4", 
	    a => "Wall, Larry",
	    ],
	[110, "1","",
	    a => "O'Reilly & Associates.",
	    ],
	[245, "9","0",
	    a => "Programming Perl / ",
	    a => "Big Book of Perl /",
	    c => "Larry Wall, Tom Christiansen & Jon Orwant.",
	    ],
	[250, "", "",
	    a => "3rd ed.",
	    ],
	[250, "", "",
	    a => "3rd ed.",
	    ],
	[260, "", "",
	    a => "Cambridge, Mass. : ",
	    b => "O'Reilly, ",
	    r => "2000.",
	    ],
	[590, "4","",
	    a => "Personally signed by Larry.",
	    ],
	[856, "4","3",
	    u => "http://www.perl.com/",
	    ],
    );
    is( $nfields, 8, "All the fields added OK" );

    my @expected = (
	q{1XX: Only one 1XX tag is allowed, but I found 2 of them.},
	q{100: Indicator 2 must be blank but it's "4"},
	q{245: Indicator 1 must be 0 or 1 but it's "9"},
	q{245: Subfield _a is not repeatable.},
	q{250: Field is not repeatable.},
	q{260: Subfield _r is not allowed.},
	q{856: Indicator 2 must be blank, 0, 1, 2 or 8 but it's "3"},
    );

    my $lint = new MARC::Lint;
    isa_ok( $lint, 'MARC::Lint' );

    $lint->check_record( $marc );
    my @warnings = $lint->warnings;
    while ( @warnings ) {
	my $expected = shift @expected;
	my $actual = shift @warnings;

	is( $actual, $expected, "Checking expected messages" );
    }
    is( scalar @expected, 0, "All expected messages exhausted." );
}
