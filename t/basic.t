use FindBin qw($Bin);
use lib "$Bin/lib";

use Test::Most;
use Catalyst::Test 'MyApp';

{
  ok my $res = request '/example1';
  is $res->code, 200;
  is $res->content, "example\n";
  is $res->content_length, 8;
  is $res->content_type, 'text/plain';
}

{
  ok my $res = request '/example2';
  is $res->code, 200;
  is $res->content, "example\n";
  is $res->content_length, 8;
  is $res->content_type, 'text/plain';
}

{
  ok my $res = request '/example3';
  is $res->code, 200;
  is $res->content, "example\n";
  is $res->content_length, 8;
  is $res->content_type, 'application/json';
}

{
  ok my $res = request '/basic/css/a.css';
  is $res->code, 200;
  is $res->content, "example\n";
  is $res->content_length, 8;
  is $res->content_type, 'text/css';
}

done_testing;
