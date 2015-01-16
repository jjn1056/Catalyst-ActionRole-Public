package MyApp::Controller::Basic;

use Moose;
use MooseX::MethodAttributes;

extends  'Catalyst::Controller';

sub absolute_path :Path('/example1') Args(0) Does(Public) At(/example.txt) { }
sub relative_path :Path('/example2') Args(0) Does(Public) At(example.txt) { }
sub set_content_type :Path('/example3') Args(0) Does(Public) ContentType(application/json) At(/:namespace/relative_path/example.txt) { }

sub css :Local Does(Public) At(/:namespace/*) { }

1;

__END__

# http://localhost/as_global/...
sub as_global :Path('/as_gobal') Does(Public) { }

#http://localhost/actionrole/...
sub test_path_prefix :Path('') Does(Public) { }

#http://localhost/actionrole/path/...
sub test_path :Path('path') Does(Public) { }

#http://localhost/actionrole/mylocal/...
sub mylocal :Local Does(Public) { }

#http://localhost/actionrole/*/aaa/link2/*/*
sub chainbase :Chained(/) PathPrefix CaptureArgs(1)  Does(Public) { }

  sub link1 :Chained(chainbase) PathPart(aaa) CaptureArgs(0) Does(Public) { }

    sub link2 :Chained(link1) Args(2) Does(Public) { }

1;
