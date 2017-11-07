use strict;
use warnings;
use Test::More;
use Net::Heroku;

use constant TEST_ONLINE  => $ENV{TEST_ONLINE};
use constant TEST_DOMAINS => $ENV{TEST_DOMAINS};


my $username = 'cpantests@gmail.com';
my $password = 'yhi8j9K^g*fo9';
my $api_key  = '836a16e3-78f4-4367-baa8-51a9753a9dca';

ok my $h = Net::Heroku->new(api_key => $api_key);

subtest auth => sub {
  plan skip_all => 'because' unless TEST_ONLINE;

  my $UUID =
    qr/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

  like +Net::Heroku->new(email => $username, password => $password)
    ->ua->api_key => $UUID;

  is +Net::Heroku->new(api_key => $api_key)->ua->api_key => $api_key;
};

subtest errors => sub {
  plan skip_all => 'because' unless TEST_ONLINE;

  # No error
  ok my %res = $h->create;
  ok !$h->error;

  # Error, empty list assignment
  ok !(my %tmp = $h->create(name => $res{name}));
  ok !keys %tmp;

  # Error from json
  ok !$h->create(name => $res{name});
  is $h->error => 'Name is already taken';

  is_deeply { $h->error } => {
    code    => 422,
    message => 'Name is already taken'
  };

  ok $h->destroy(name => $res{name});

  # Error from body
  ok !$h->destroy(name => $res{name});
  is $h->error => 'Couldn\'t find that app.';

  is_deeply { $h->error } => {
    code    => 404,
    message => 'Couldn\'t find that app.'
  };
};

subtest domains => sub {
  plan skip_all => 'Requires verified account with credit card'
    unless TEST_DOMAINS;

  ok my %res = $h->create;

  ok my $default_domain = [$h->domains(name => $res{name})]->[0];
  is $default_domain->{domain} => $res{domain_name}->{domain};

  ok !$h->add_domain(name => $res{name}, domain => 'mojocasts.com');
  is $h->error => 'mojocasts.com is currently in use by another app.';

  my $domain = 'domain-name-for-' . $res{name} . '.com';
  ok !$h->add_domain(name => $res{name}, domain => $domain);
  ok grep $_->{base_domain} eq $domain => $h->domains(name => $res{name});

  ok $h->remove_domain(name => $res{name}, domain => $domain);
  is_deeply $default_domain => [$h->domains(name => $res{name})]->[0];

  ok $h->destroy(name => $res{name});
};

subtest apps => sub {
  plan skip_all => 'because' unless TEST_ONLINE;

  ok my %res = $h->create(stack => 'cedar-14');
  like $res{stack}{name} => qr/^cedar-14/;

  ok grep $_->{name} eq $res{name} => $h->apps;

  ok $h->destroy(name => $res{name});
  ok !grep $_->{name} eq $res{name} => $h->apps;

  # Do not fail with empty names
  #ok %res = $h->create(name => '');
  #ok $res{name};
  #ok $h->destroy(name => $res{name});
};

subtest config => sub {
  plan skip_all => 'because' unless TEST_ONLINE;

  ok my %res = $h->create;

  is { $h->add_config(name => $res{name}, TEST_CONFIG => 'Net-Heroku') }
    ->{TEST_CONFIG} => 'Net-Heroku';

  is { $h->config(name => $res{name}) }->{TEST_CONFIG} => 'Net-Heroku';

  ok $h->destroy(name => $res{name});
};

subtest keys => sub {
  plan skip_all => 'because' unless TEST_ONLINE;

  my $key =
    'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAAgQCwiIC7DZYfPbSn/O82ei262gnExmsvx27nkmNgl5scyYhJjwMkZrl66zofAkwsydxl+7fNfKio+FsdutNva4yVruk011fzKU+Nsa5jEe0MF/x0e6QwBLtq9QthWomgvoNccV9g3TkkjykCFQQ7aLId1Wur0B+MzwCIVZ5Cm/+K2w== cpantests-net-heroku';

  ok my %added_key = $h->add_key(key => $key);
  ok grep $_->{public_key} eq $key => $h->keys;

  $h->remove_key(key_id => $added_key{id});
  ok !grep $_->{public_key} eq $key => $h->keys;
};

subtest processes => sub {
  plan skip_all => 'because' unless TEST_ONLINE;

  ok my %res = $h->create;

  # List of processes
  ok !$h->ps(name => $res{name});

  # Create dyno
  ok my %ps = $h->ps_create(name => $res{name}, command => 'ls');

  # Get dyno info by name
  ok $h->ps(name => $res{name}, dyno => $ps{name});

  # No run in new heroku API?
  # Run process
  #is { $h->run(name => $res{name}, command => 'ls') }->{state} => 'starting';

  # Restart app
  ok $h->restart(name => $res{name}), 'restart app';

  # Restart process
  ok $h->restart(name => $res{name}, dyno => $ps{name}), 'restart app process';

  # Stop process
  ok $h->stop(name => $res{name}, dyno => $ps{name}), 'stop app process';

  ok $h->destroy(name => $res{name});
};

subtest releases => sub {
  plan skip_all => 'because' unless TEST_ONLINE;

  ok my %res = $h->create;

  # Wait until server process finishes adding add-ons (v2 release)
  for (1 .. 5) {
    last if $h->releases(name => $res{name}) == 2;
    sleep 1;
  }

  # Add buildpack to increment release
  ok $h->add_config(
    name          => $res{name},
    BUILDPACK_URL => 'http://github.com/tempire/perloku.git'
  );

  # List of releases
  my @releases = $h->releases(name => $res{name});
  ok grep $_->{description} eq 'Set BUILDPACK_URL config vars' => @releases;

  # One release by id
  my %release =
    $h->releases(name => $res{name}, release => $releases[-1]{id});
  is $release{id} => $releases[-1]{id};

  # Rollback to a previous release
  my $previous_release = $releases[-2];
  is $h->rollback(name => $res{name}, release => $previous_release->{id}) =>
    $previous_release->{id};

  ok $h->destroy(name => $res{name});
};

done_testing;
