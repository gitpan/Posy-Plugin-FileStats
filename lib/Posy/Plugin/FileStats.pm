package Posy::Plugin::FileStats;
use strict;

=head1 NAME

Posy::Plugin::FileStats - Posy plugin to cache file statistics.

=head1 VERSION

This describes version B<0.51> of Posy::Plugin::FileStats.

=cut

our $VERSION = '0.51';

=head1 SYNOPSIS

    @plugins = qw(Posy::Core
		  ...
		  Posy::Plugin::FileStats
		  ...
		  ));
    @actions = qw(
	....
	index_entries
	index_file_stats
	...
	);

=head1 DESCRIPTION

This is a "utility" plugin to be used by other plugins; it maintains a list
(and cache) of file statistics in $self->{file_stats} which can be used by
other plugins (such as Posy::Plugin::LinkSized).

It provides an action method L</index_file_stats> which should be put
after "index_entries" in the action list.

The file_stats hash is referenced by the full name of the file.

The statistics kept are:

=over

=item size

The size of the file in bytes.

=item size_string

The size of the file as a string (with K or M as appropriate).

=item mime_type

The MIME type of the file.

=item mtime

The modification time of the file.

=item word_count

The word-count of text and HTML files.

=back

=head2 Configuration

The following config values can be set:

=over

=item B<file_stats_cachefile>

The full name of the file to be used to store the cache.
Most people can just leave this at the default.

=back

=head2 Parameters

This plugin will do reindexing the first time it is run, or
if it detects that there are files in the main file index which
are new.  Full or partial reindexing can be forced by setting the
the following parameters.

=over

=item reindex_all

    /cgi-bin/posy.cgi?reindex_all=1

Does a full reindex of all files in the data_dir directory,
clearing the old data and starting again.

=item reindex

    /cgi-bin/posy.cgi?reindex=1

Does an additive reindex of all files in the data_dir directory;
new files get added, data for existing files remains the same.

=item reindex_cat

    /cgi-bin/posy.cgi?reindex_cat=stories/buffy

Does a reindex of all files under the given category.  Does not
delete files from the index.  Useful to call when you know you've just
updated/added files in a particular category index, and don't want to have
to reindex the whole site.

=item delindex

    /cgi-bin/posy.cgi?delindex=1

Deletes files from the index if they no longer exist.  Useful when you've
deleted files but don't want to have to reindex the whole site.

=back

=cut
use File::MMagic;
use File::stat;

=head1 OBJECT METHODS

Documentation for developers and those wishing to write plugins.

=head2 init

Do some initialization; make sure that default config values are set.

=cut
sub init {
    my $self = shift;
    $self->SUPER::init();

    # set defaults
    $self->{config}->{file_stats_cachefile} ||=
	File::Spec->catfile($self->{state_dir}, 'file_stats.dat');
} # init


=head1 Flow Action Methods

Methods implementing actions.

=head2 index_file_stats

Find statistics about entry and other files.

Expects $self->{config}, $self->{files}
and $self->{others} to be set.

=cut

sub index_file_stats {
    my $self = shift;
    my $flow_state = shift;

    my $reindex_all = $self->param('reindex_all');
    my $reindex = $self->param('reindex');
    $reindex_all = 1 if (!$self->_fs_init_caching());
    if (!$reindex_all)
    {
	$reindex_all = 1 if (!$self->_fs_read_cache());
    }
    # check for a partial reindex
    my $reindex_cat = $self->param('reindex_cat');
    # make sure there's no extraneous slashes
    $reindex_cat =~ s{^/}{};
    $reindex_cat =~ s{/$}{};
    if (!$reindex_all
	and $reindex_cat
	and exists $self->{categories}->{$reindex_cat}
	and defined $self->{categories}->{$reindex_cat})
    {
	$self->debug(1, "file_stats: reindexing $reindex_cat");
	# do a partial reindex
	while (my $file_id = each %{$self->{files}})
	{
	    if (($self->{files}->{$file_id}->{cat_id} eq $reindex_cat)
		or ($self->{files}->{$file_id}->{cat_id}
		    =~ /^$reindex_cat/)
	       )
	    {
		my $fullname = $self->{files}->{$file_id}->{fullname};
		$self->_fs_set_stats($fullname);
	    }
	}
	while (my $fullname = each %{$self->{others}})
	{
	    if (($self->{others}->{$fullname} eq $reindex_cat)
		or ($self->{others}->{$fullname} =~ /^$reindex_cat/)
	       )
	    {
		$self->_fs_set_stats($fullname);
	    }
	}
	$self->_fs_save_cache();
    }
    elsif (!$reindex_all)
    {
	# If any files are in $self->{files} but not in
	# $self->{file_stats}, set stats for them
	my $newfiles = 0;
	while (my $file_id = each %{$self->{files}})
	{ exists $self->{file_stats}->{$self->{files}->{$file_id}->{fullname}}
	    or do {
		$newfiles++;
		$self->_fs_set_stats($self->{files}->{$file_id}->{fullname});
		$self->debug(2, "FileStats: added $file_id");
	    };
	}
	# If any files are in $self->{others} but not in
	# $self->{file_stats}, set stats for them
	while (my $fullname = each %{$self->{others}})
	{ exists $self->{file_stats}->{$fullname}
	    or -d $fullname
	    or do {
		$newfiles++;
		$self->_fs_set_stats($fullname);
		$self->debug(2, "FileStats: added $fullname");
	    };
	}
	$self->debug(1, "FileStats: added $newfiles new files") if $newfiles;
	$self->_fs_save_cache() if $newfiles;
    }

    if ($reindex_all) {
	$self->{file_stats} = {};
	$self->debug(1, "FileStats: reindexing ALL");
	while (my $file_id = each %{$self->{files}})
	{
	    my $fullname = $self->{files}->{$file_id}->{fullname};
	    $self->_fs_set_stats($fullname);
	}
	while (my $fullname = each %{$self->{others}})
	{
	    $self->_fs_set_stats($fullname);
	}
	$self->_fs_save_cache();
    }
    else
    {
	# If any files not available, delete them and just save the cache
	if ($self->param('delindex'))
	{
	    $self->debug(1, "FileStats: checking for deleted files");
	    my $deletions = 0;
	    while (my $fullname = each %{$self->{file_stats}})
	    { -f $fullname
		or do { $deletions++; delete $self->{file_stats}->{$fullname} };
	    }
	    $self->debug(1, "FileStats: deleted $deletions gone files")
		if $deletions;
	    $self->_fs_save_cache() if $deletions;
	}
    }
} # index_file_stats

=head1 Helper Methods

Methods which can be called from elsewhere.

=head2 get_mime_type

    $mime_type = $self->get_mime_type($fullname);

Get the MIME type of the given file.

=cut
sub get_mime_type {
    my $self = shift;
    my $fullname = shift;

    my $mime_type = 'text/plain';

    # find the mime type
    my $mm = new File::MMagic;
    $mime_type = $mm->checktype_filename($fullname);
    return $mime_type;
} # get_mime_type

=head2 get_word_count

    $word_count = $self->get_word_count($fullname, $mime_type);

Get the word-count of the given file.

=cut
sub get_word_count {
    my $self = shift;
    my $fullname = shift;
    my $mime_type = shift;

    my $word_count = 0;
    if ($mime_type =~ m#^text/plain#)
    {
	my $fh;
	local $/;
	open($fh, $fullname) or return 0;
	my $data = <$fh>;
	close($fh);
	my @words = split(' ', $data);
	$word_count = @words;
    }
    elsif ($mime_type =~ m#^text/html#)
    {
	my $fh;
	local $/;
	open($fh, $fullname) or return 0;
	my $data = <$fh>;
	close($fh);
	$data =~ m#<body[^>]*>(.*)</body>#is;
	my $body = $1; # just the body
	$body =~ s/<[^>]+>//sg; # remove HTML tags
	$body =~ s/\s\s+/ /g;
	my @words = split(' ', $body);
	$word_count = @words;
    }

    return $word_count;
} # get_word_count

=head1 Private Methods

Methods which may or may not be here in future.

=head2 _fs_set_stats

$self->_fs_set_stats($fullname);

Set the stats for one file.

=cut
sub _fs_set_stats {
    my $self = shift;
    my $fullname = shift;

    if (-f $fullname)
    {
	my $st = stat($fullname);

	$self->{file_stats}->{$fullname}->{size} = $st->size;
	$self->{file_stats}->{$fullname}->{size_string} =
	    $self->_size_string($st->size);
	$self->{file_stats}->{$fullname}->{mime_type} =
	    $self->get_mime_type($fullname);
	$self->{file_stats}->{$fullname}->{word_count} =
	    $self->get_word_count($fullname,
				  $self->{file_stats}->{$fullname}->{mime_type});
	$self->{file_stats}->{$fullname}->{mtime} = $st->mtime;
    }
    else # does not exist, delete it
    {
	delete $self->{file_stats}->{$fullname};
    }
} # _fs_set_stats

=head2 _size_string

    $size_str = $self->_size_string($size);

Given a size in bytes, give a human-friendly size string
(for example, so many K).

=cut
sub _size_string {
    my $self = shift;
    my $size = shift;

    my $size_str = $size;
    if ($size >= 1048576)
    {
        $size /= 1048576;
	$size_str = sprintf("%.1fM", $size);
    }
    elsif ($size >= 1024)
    {
        $size /= 1024;
	$size_str = int($size);
	$size_str .= 'K';
    }
    else
    {
	$size_str = $size . 'b';
    }
    return $size_str;
} # _size_string

=head2 _fs_init_caching

Initialize the caching stuff used by index_entries

=cut
sub _fs_init_caching {
    my $self = shift;

    return 0 if (!$self->{config}->{use_caching});
    eval "require Storable";
    if ($@) {
	$self->debug(1, "FileStats: cache disabled, Storable not available"); 
	$self->{config}->{use_caching} = 0; 
	return 0;
    }
    if (!Storable->can('lock_retrieve')) {
	$self->debug(1, "FileStats: cache disabled, Storable::lock_retrieve not available");
	$self->{config}->{use_caching} = 0;
	return 0;
    }
    $self->debug(1, "FileStats: using caching");
    return 1;
} # _fs_init_caching

=head2 _fs_read_cache

Reads the cached information used by index_entries

=cut
sub _fs_read_cache {
    my $self = shift;

    return 0 if (!$self->{config}->{use_caching});
    $self->{file_stats} = (-r $self->{config}->{file_stats_cachefile}
	? Storable::lock_retrieve($self->{config}->{file_stats_cachefile}) : undef);
    if ($self->{file_stats}) {
	$self->debug(1, "FileStats: Using cached state");
	return 1;
    }
    $self->{file_stats} = {};
    $self->debug(1, "FileStats: Flushing caches");
    return 0;
} # _fs_read_cache

=head2 _fs_save_cache

Saved the information gathered by index_entries to caches.

=cut
sub _fs_save_cache {
    my $self = shift;
    return if (!$self->{config}->{use_caching});
    $self->debug(1, "FileStats: Saving caches");
    Storable::lock_store($self->{file_stats}, $self->{config}->{file_stats_cachefile});
} # _fs_save_cache

=head1 INSTALLATION

Installation needs will vary depending on the particular setup a person
has.

=head2 Administrator, Automatic

If you are the administrator of the system, then the dead simple method of
installing the modules is to use the CPAN or CPANPLUS system.

    cpanp -i Posy::Plugin::FileStats

This will install this plugin in the usual places where modules get
installed when one is using CPAN(PLUS).

=head2 Administrator, By Hand

If you are the administrator of the system, but don't wish to use the
CPAN(PLUS) method, then this is for you.  Take the *.tar.gz file
and untar it in a suitable directory.

To install this module, run the following commands:

    perl Build.PL
    ./Build
    ./Build test
    ./Build install

Or, if you're on a platform (like DOS or Windows) that doesn't like the
"./" notation, you can do this:

   perl Build.PL
   perl Build
   perl Build test
   perl Build install

=head2 User With Shell Access

If you are a user on a system, and don't have root/administrator access,
you need to install Posy somewhere other than the default place (since you
don't have access to it).  However, if you have shell access to the system,
then you can install it in your home directory.

Say your home directory is "/home/fred", and you want to install the
modules into a subdirectory called "perl".

Download the *.tar.gz file and untar it in a suitable directory.

    perl Build.PL --install_base /home/fred/perl
    ./Build
    ./Build test
    ./Build install

This will install the files underneath /home/fred/perl.

You will then need to make sure that you alter the PERL5LIB variable to
find the modules, and the PATH variable to find the scripts (posy_one,
posy_static).

Therefore you will need to change:
your path, to include /home/fred/perl/script (where the script will be)

	PATH=/home/fred/perl/script:${PATH}

the PERL5LIB variable to add /home/fred/perl/lib

	PERL5LIB=/home/fred/perl/lib:${PERL5LIB}

=head1 REQUIRES

    Posy
    Posy::Core

    File::stat
    File::MMagic

    Test::More

=head1 SEE ALSO

perl(1).
Posy

=head1 BUGS

Please report any bugs or feature requests to the author.

=head1 AUTHOR

    Kathryn Andersen (RUBYKAT)
    perlkat AT katspace dot com
    http://www.katspace.com

=head1 COPYRIGHT AND LICENCE

Copyright (c) 2005 by Kathryn Andersen

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Posy::Plugin::FileStats
__END__
