package Posy::Plugin::FileStats;
use strict;

=head1 NAME

Posy::Plugin::FileStats - Posy plugin to cache file statistics

=head1 VERSION

This describes version B<0.40> of Posy::Plugin::FileStats.

=cut

our $VERSION = '0.40';

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

For convenience, copies the mtime from $self->{files} or $self->{others}
for the given file.

=item word_count

The word-count of text and HTML files.

=back

=head1 Configuration

The following config values can be set:

=over

=item B<file_stats_cachefile>

The full name of the file to be used to store the cache.
Most people can just leave this at the default.

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

    my $reindex = $self->param('reindex');
    $reindex = 1 if (!$self->_fs_init_caching());
    if (!$reindex)
    {
	$reindex = 1 if (!$self->_fs_read_cache());
    }
    # If any files are in $self->{files} but not in
    # $self->{file_stats}, reindex
    for my $ffn (keys %{$self->{files}})
    { exists $self->{file_stats}->{$self->{files}->{$ffn}->{fullname}}
	or do { $reindex++; delete $self->{file_stats}->{
	    $self->{files}->{$ffn}->{fullname}} }; }
    # If any files are in $self->{others} but not in
    # $self->{file_stats}, reindex
    for my $fln (keys %{$self->{others}})
    { exists $self->{file_stats}->{$fln}
	or do { $reindex++; delete $self->{file_stats}->{$fln} }; }

    if ($reindex) {
	foreach my $file_id (keys %{$self->{files}})
	{
	    my $fullname = $self->{files}->{$file_id}->{fullname};
	    my $st = stat($fullname);

	    $self->{file_stats}->{$fullname}->{size} = $st->size;
	    $self->{file_stats}->{$fullname}->{size_string} =
		$self->_size_string($st->size);
	    $self->{file_stats}->{$fullname}->{mime_type} =
		$self->get_mime_type($fullname);
	    $self->{file_stats}->{$fullname}->{word_count} =
		$self->get_word_count($fullname,
		$self->{file_stats}->{$fullname}->{mime_type});
	    $self->{file_stats}->{$fullname}->{mtime} = 
		$self->{files}->{$file_id}->{mtime};
	}
	foreach my $fullname (keys %{$self->{others}})
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
	    $self->{file_stats}->{$fullname}->{mtime} = 
		$self->{others}->{$fullname};
	}
	$self->_fs_save_cache();
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
	$data =~ s/<[^>]+>//sg; # remove HTML tags
	my @words = split(' ', $data);
	$word_count = @words;
    }

    return $word_count;
} # get_word_count

=head1 Private Methods

Methods which may or may not be here in future.

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
