package Catalyst::ActionRole::Public;

use Moose::Role;
use Plack::Util ();
use Cwd ();
use Plack::MIME ();
use HTTP::Date ();

requires 'execute', 'match';

has at => (
  is=>'ro',
  required=>1,
  lazy=>1,
  builder=>'_build_at');

  sub _build_at {
    my ($self) = @_;
    my ($at) = (@{$self->attributes->{At}||['/:privatepath/:args']});
    return $at;
  }

has content_type => (
  is=>'ro',
  lazy=>1,
  builder=>'_build_content_type');

  sub _build_content_type {
    my ($self) = @_;
    my ($ct) = (@{$self->attributes->{ContentType}||[]});
    return $ct;
  }

has show_debugging => (
  is=>'ro',
  required=>1,
  lazy=>1,
  builder=>'_build_show_debugging');

  sub _build_show_debugging {
    my ($self) = @_;
    return exists $self->attributes->{ShowDebugging} ? 1:0;
  }

sub expand_at_template {
  my ($self, $at, %args) = @_;
  return my @at_parts =
    map { ref $_ ? @$_ : $_ } 
    map { defined($args{$_}) ? $args{$_} : $_ }
    split('/', $at);
}

sub expand_if_relative_path {
  my ($self, @path_parts) = @_;
  unless($path_parts[0]) {
    return @path_parts[1..$#path_parts];
  } else {
    return (split('/', $self->private_path), @path_parts);
  }
}

sub is_real_file {
  my ($self, $path) = @_;
  return -f $path ? 1:0;
}

sub evil_args {
  my ($self, @args) = @_;
  foreach my $arg(@args) {
    return 1 if $arg eq '..';
  }
  return 0;
}

around 'match' => sub {
  my ($orig, $self, $ctx) = @_;
  my @args = @{$ctx->req->args||[]};
  return 0 if($self->evil_args(@args));

  my %template_args = (
    ':namespace' => $self->namespace,
    ':privatepath' => $self->private_path,
    ':args' => \@args,
    '*' => \@args);

  my @path_parts = $self->expand_if_relative_path( 
    $self->expand_at_template($self->at, %template_args));

  $ctx->stash(public_file_path => 
    (my $full_path = $ctx->{root}->file(@path_parts)));

  $ctx->log->debug("Requested File: $full_path") if $ctx->debug;
  
  if($self->is_real_file($full_path)) {
    $ctx->log->debug("Serving File: $full_path") if $ctx->debug;
    return $self->$orig($ctx);
  } else {
    $ctx->log->debug("File Not Found: $full_path") if $ctx->debug;
    return 0;
  }
};

around 'execute', sub {
  my ($orig, $self, $controller, $ctx, @args) = @_;
  $ctx->log->abort(1) unless $self->show_debugging;
  my $fh = $ctx->stash->{public_file_path}->openr;
  Plack::Util::set_io_path($fh, Cwd::realpath($ctx->stash->{public_file_path}));

  my $stat = $ctx->stash->{public_file_path}->stat;
  my $content_type = $self->content_type || Plack::MIME->mime_type($ctx->stash->{public_file_path})
    || 'application/octet';

  $ctx->res->from_psgi_response([
    200,
    [
      'Content-Type'   => $content_type,
      'Content-Length' => $stat->[7],
      'Last-Modified'  => HTTP::Date::time2str( $stat->[9] )
    ],
    $fh]);

  return $self->$orig($controller, $ctx, @args);
};

1;

=head1 TITLE

Catalyst::ActionRole::Public - mount a public url to files in your Catalyst project

=head1 SYNOPSIS

    package MyApp::Controller::Root;

    use Moose;
    use MooseX::MethodAttributes;

    sub static :Local Does(Public) { ... }

    __PACKAGE__->config(namespace=>'');

Will create an action that from URL 'localhost/static/a/b/c/d.js' will serve
file $c->{root} . '/static' . '/a/b/c/d.js'.  Will also set content type, length
and Last-Modified HTTP headers as needed.  If the file does not exist, will not
match (allowing possibly other actions to match).

=head1 DESCRIPTION

Use this actionrole to map a public facing URL attached to an action to a file
(or files) on the filesystem, off the $c->{root} directory.  If the file does
not exist, the action will not match.  No default 'notfound' page is created,
unlike L<Plack::App::File> or L<Catalyst::Plugin::Static::Simple>.  The action
method body may be used to modify the response before finalization.  A template
may be constructed 

=head2 ACTION METHOD BODY

The body of your action will be executed after we've created a filehandle to
the found file and setup the response.  You may leave it empty, or if you want
to do additional logging or work, you can. Also, you will find a stash key 
C<public_file_path> has been populated with a L<Path::Class> object which is
pointing to the found file.  The action method body will not be executed if
the file associated with the action does not exist.

=head1 ACTION ATTRIBUTES

Actions the consume this role provide the following subroutine attributes.

=head2 ShowDebugging

Enabled developer debugging output.  Example:

    sub myaction :Local Does(Public) ShowDebugging { ... }

If present do not surpress the extra developer mode debugging information.  Useful
if you have trouble serving files and you can't figure out why.

=head2 At 

Used to set the action class template used to match files on the filesystem to
incoming requests.  Examples:

    TBD

B<NOTE:> The following expansions are recognized in your C<At> declaration:

=over 4

=item :namespace

The action namespace, determined from the containing controller.  Usually this
is based on the Controller package name but you can override it via controller
configuration.  For example:

    package MyApp::Controller::Foo::Bar::Baz;

Has a namespace of 'foo/bar/baz' by default.

=item :privatepath

The action private_path value.  By default this is the namespace + the action
name.  For example:

    package MyApp::Controller::Foo::Bar::Baz;

    sub myaction :Path('abcd') { ... }

The action C<myaction> has a private_path of '/foo/bar/baz/myaction'.

B<NOTE:> the expansion C<:private_path> is mapped to this value as well.

=item :args

=item *

The arguments to the request.  For example:

    Package MyApp::Controller::Static;

    sub myfiles :Path('') Does(Public) At(/:namespace/*) { ... }

Would map 'http://localhost/static/a/b/c/d.txt' to $c->{root} . '/static/a/b/c/d.txt'.\

In this case $args = ['a', 'b', 'c', 'd.txt']

=back

=head2 ContentType

Used to set the respone Content-Type header. Example:

    sub myaction :Local Does(Public) ShowDebugging { ... }

By default we inspect the request URL extension and set a content type based on
the extension text (defaulting to 'application/octet' if we cannot determine.  If
you set this to a MIME type, we will alway set the response content type based on
this, no matter what the extension, if any, says.

=head1 AUTHOR
 
John Napiorkowski L<email:jjnapiork@cpan.org>
  
=head1 SEE ALSO
 
L<Catalyst>, L<Catalyst::Controller>, L<Plack::App::Directory>,
L<Catalyst::Controller::Assets>.
 
=head1 COPYRIGHT & LICENSE
 
Copyright 2015, John Napiorkowski L<email:jjnapiork@cpan.org>
 
This library is free software; you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

__END__

ContentType
