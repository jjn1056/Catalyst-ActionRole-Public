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

around ['match', 'match_captures'] => sub {
  my ($orig, $self, $ctx, $captures) = @_;
  # ->match does not get args :( but ->match_captures get captures...
  my @args = defined($captures) ? @$captures : @{$ctx->req->args||[]};
  return 0 if($self->evil_args(@args));

  my %template_args = (
    ':namespace' => $self->namespace,
    ':privatepath' => $self->private_path,
    ':private_path' => $self->private_path,
    ':actionname' => $self->name,
    ':action_name' => $self->name,
    ':args' => \@args,
    '*' => \@args);

  my @path_parts = $self->expand_if_relative_path( 
    $self->expand_at_template($self->at, %template_args));

  $ctx->stash(public_file_path => 
    (my $full_path = $ctx->{root}->file(@path_parts)));

  $ctx->log->debug("Requested File: $full_path") if $ctx->debug;
  
  if($self->is_real_file($full_path)) {
    $ctx->log->debug("Serving File: $full_path") if $ctx->debug;
    return $self->$orig($ctx, $captures);
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

    sub static :Local Does(Public) At(/:actionname/*) { ... }

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
method body may be used to modify the response before finalization.

A template may be constructed to determine how we map an incoming request to
a path on the filesystem.  You have extensive control how an incoming HTTP
request maps to a file on the filesystem.  You can even use this action role
in the middle of a chained style action (although its hard to imagine the
use case for that...)

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

    package MyApp::Controller::Basic;

    use Moose;
    use MooseX::MethodAttributes;

    extends  'Catalyst::Controller';

    #localhost/basic/css => $c->{root} .'/basic/*'
    sub css :Local Does(Public) At(/:namespace/*) { }

    #localhost/basic/static => $c->{root} .'/basic/static/*'
    sub static :Local Does(Public) { }

    #localhost/basic/111/aaa/link2/333/444.txt => $c->{root} .'/basic/link2/333/444.txt'
    sub chainbase :Chained(/) PathPrefix CaptureArgs(1) { }

      sub link1 :Chained(chainbase) PathPart(aaa) CaptureArgs(0) { }

        sub link2 :Chained(link1) Args(2) Does(Public) { }

    #localhost/chainbase2/111/aaa/222.txt/link4/333 => $c->{root} . '/basic/link3/222.txt'
    sub chainbase2 :Chained(/)  CaptureArgs(1) { }

      sub link3 :Chained(chainbase2) PathPart(aaa) CaptureArgs(1) Does(Public) { }

        sub link4 :Chained(link3) Args(1)  { }

    1;

B<NOTE:> You're template may be 'relative or absolute' to the $c->{root} value
based on if the first character in the template is '/' or not.   If it is '/'
that is an 'absolute' template which will be added to $c->{root}.  Generally
if you are making a template this is what you want.  However if you don't have
a '/' prepended to the start of your template (such as in At(file.txt)) we then
make your filesystem lookup relative to the action private path.  So in the
example:

    package MyApp::Controller::Basic;

    sub absolute_path :Path('/example1') Does(Public) At(/example.txt) { }
    sub relative_path :Path('/example2') Does(Public) At(example.txt) { }

Then http://localhost/example1 => $c->{root} . '/example.txt' but
http://localhost/example2 => $c->{root} . '/basic/relative_path/example.txt'.
You may find this a useful "DWIW" when an action is linked to a particular file.

B<NOTE:> The following expansions are recognized in your C<At> declaration:

=over 4

=item :namespace

The action namespace, determined from the containing controller.  Usually this
is based on the Controller package name but you can override it via controller
configuration.  For example:

    package MyApp::Controller::Foo::Bar::Baz;

Has a namespace of 'foo/bar/baz' by default.

=item :privatepath

=item :private_path

The action private_path value.  By default this is the namespace + the action
name.  For example:

    package MyApp::Controller::Foo::Bar::Baz;

    sub myaction :Path('abcd') { ... }

The action C<myaction> has a private_path of '/foo/bar/baz/myaction'.

B<NOTE:> the expansion C<:private_path> is mapped to this value as well.

=item actionname

=item action_name

The name of the action (typically the subroutine name)

    sub static :Local Does(Public) At(/:actionname/*) { ... }

In this case actionname = 'static'

=item :args

=item '*'

The arguments to the request.  For example:

    Package MyApp::Controller::Static;

    sub myfiles :Path('') Does(Public) At(/:namespace/*) { ... }

Would map 'http://localhost/static/a/b/c/d.txt' to $c->{root} . '/static/a/b/c/d.txt'.

In this case $args = ['a', 'b', 'c', 'd.txt']

=back

=head2 ContentType

Used to set the respone Content-Type header. Example:

    sub myaction :Local Does(Public) ShowDebugging { ... }

By default we inspect the request URL extension and set a content type based on
the extension text (defaulting to 'application/octet' if we cannot determine.  If
you set this to a MIME type, we will alway set the response content type based on
this, no matter what the extension, if any, says.

=head1 RESPONSE INFO

If we find a file we serve the filehandle directly to you plack handler, and set
a 'with_path' value so that you can use this with something like L<Plack::Middleware::XSendfile>.
We also set the Content-Type, Content-Length and Last-Modified headers.  If you
need to add more information before finalizing the response you may do so with
the matching action metod body.

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
