use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Posy::Plugin::FileStats',
    license             => 'perl',
    dist_author         => 'Kathryn Andersen',
    dist_version_from   => 'lib/Posy/Plugin/FileStats.pm',
	requires            => {
	'Posy' => 0.91,
	'File::stat' => 1.00,
	'File::MMagic' => 1.22,
	},
    build_requires => {
        'Test::More' => 0,
    },
);

$builder->create_build_script();
