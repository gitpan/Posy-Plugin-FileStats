# Test distribution before release
# Optional for end users if Test::Distribution not installed

use Test::More;

BEGIN {
    eval {
	require Text::Template;
	require HTML::TextToHTML;
	require YAML;
	require File::MMagic;
    };
    if ($@) {
	plan skip_all => "modules needed for certain plugin modules not installed";
    }
    else
    {
	eval {
	    require Test::Distribution;
	};
	if($@) {
	    plan skip_all => "Test::Distribution not installed";
	}
	else {
	    import Test::Distribution;
	}
    }
}
