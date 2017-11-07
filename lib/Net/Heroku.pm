package Net::Heroku;
use Mojo::Base -base;
use Net::Heroku::UserAgent;
use Mojo::JSON qw(encode_json);
use Mojo::Util qw(url_escape b64_encode);

our $VERSION = 0.20;

has host => 'api.heroku.com';
has ua => sub { Net::Heroku::UserAgent->new(host => shift->host) };
has 'api_key';

sub new {
  my $self   = shift->SUPER::new(@_);
  my %params = @_;

  # Assume email & pass
  $self->ua->api_key(
    defined $params{email} && defined $params{password}
    ? $self->_retrieve_token(@params{qw/ email password /})
    : $params{api_key}
      ? $params{api_key}
      : ''
  );

  # Simple auth test
  die 'Invalid API key'
    if $self->ua->get('/apps')->result->code == 401;

  return $self;
}

sub error {
  my $self = shift;
  my $res  = $self->ua->tx->result;

  return if $res->code =~ /^2\d{2}$/;

  return (
    code    => $res->code,
    #id      => ($res->json ? $res->json->{id} : ''),
    message => ($res->json ? $res->json->{message} : $res->body),
  );
}

# actually retrieving a token now
sub _retrieve_token {
  my ($self, $email, $password) = @_;

  return $self->ua->post(
    '/oauth/authorizations' =>
    { Authorization => 'Basic ' . b64_encode("$email:$password", "") }
  )->result->json('/access_token/token');
}

sub apps {
  my ($self, $name) = @_;

  return @{$self->ua->get('/apps')->res->json || []};
}

# create actually returns a 201 status now when app is created
sub app_created {
  my ($self, %params) = (shift, @_);

  return 1
    if $self->ua->get('/apps/' . $params{name})->result->code == 200;
}

sub destroy {
  my ($self, %params) = @_;

  my $res = $self->ua->delete('/apps/' . $params{name})->result;
  return 1 if $res->{code} == 200;
}

sub create {
  my ($self, %params) = (shift, @_);

  my $res = $self->ua->post('/apps' => json => \%params)->result;

  return $res->json && $res->code == 201 ? %{$res->json} : ();
}

sub add_config {
  my ($self, %params) = (shift, @_);

  return %{
    $self->ua->patch(
        '/apps/'
      . (defined $params{name} and delete($params{name}))
      . '/config-vars' =>
      json => \%params
    )->result->json
    || {}
  };
}

sub config {
  my ($self, %params) = (shift, @_);

  return %{
    $self->ua->get('/apps/' . $params{name} . '/config-vars')->result->json
    || []
  };
}

sub add_key {
  my ($self, %params) = (shift, @_);

  return %{
    $self->ua->post(
      '/account/keys' => json => { public_key => $params{key} }
    )->result->json
  };
}

sub keys {
  my ($self, %params) = (shift, @_);

  return @{$self->ua->get('/account/keys')->result->json || []};
}

# needs to use key id now
sub remove_key {
  my ($self, %params) = (shift, @_);

  my $res =
    $self->ua->delete('/account/keys/' . url_escape($params{key_id}))->result;
  return 1 if $res->{code} == 200;
}

sub ps {
  my ($self, %params) = (shift, @_);

  my $url =
      '/apps/'
    . $params{name}
    . '/dynos'
    . ($params{dyno} ? '/' . $params{dyno} : '');

  my $ps = $self->ua->get($url)->result->json || [];

  return $params{dyno} ? %$ps : @$ps;
}

sub ps_create {
  my ($self, %params) = (shift, @_);

  return %{
    $self->ua->post(
        '/apps/'
      . (defined $params{name} and delete($params{name}))
      . '/dynos' =>
      json => \%params
    )->result->json
    || {}
  };
}

sub restart {
  my ($self, %params) = (shift, @_);

  return 1
    if $self->ua->delete(
        '/apps/'
      . $params{name}
      . '/dynos'
      . ($params{dyno} ? '/' . $params{dyno} : '')
    )->result->code == 202;
}

sub stop {
  my ($self, %params) = (shift, @_);

  return 1
    if $self->ua->post(
        '/apps/'
      . $params{name}
      . '/dynos/'
      . $params{dyno}
      . '/actions/stop'
    )->result->code == 202;
}

sub releases {
  my ($self, %params) = (shift, @_);

  my $url =
      '/apps/'
    . $params{name}
    . '/releases'
    . ($params{release} ? '/' . $params{release} : '');

  my $releases = $self->ua->get($url)->result->json || [];

  return $params{release} ? %$releases : @$releases;
}

sub rollback {
  my ($self, %params) = (shift, @_);

  return $params{release}
    if $self->ua->post(
        '/apps/'
      . (defined $params{name} and delete($params{name}))
      . '/releases' => json => \%params
    )->result->code == 201;
}

sub add_domain {
  my ($self, %params) = (shift, @_);

  my $url = '/apps/' . $params{name} . '/domains';

  return 1
    if $self->ua->post(
      $url => json => { hostname => $params{domain} }
    )->result->code == 201;
}

sub domains {
  my ($self, %params) = (shift, @_);

  my $url = '/apps/' . $params{name} . '/domains';

  return @{$self->ua->get($url)->result->json || []};
}

sub remove_domain {
  my ($self, %params) = (shift, @_);

  return 1
    if $self->ua->delete(
      '/apps/' . $params{name} . '/domains/' . url_escape($params{domain})
    )->result->code == 200;
}

1;

=head1 NAME

Net::Heroku - Heroku API

=head1 DESCRIPTION

Heroku API

Requires Heroku account - free @ L<http://heroku.com>

Domain functions are untested with new API (v0.20+).

=head1 USAGE

    my $h = Net::Heroku->new(api_key => api_key);
    - or -
    my $h = Net::Heroku->new(email => $email, password => $password);

    my %res = $h->create;

    $h->add_config(name => $res{name}, BUILDPACK_URL => ...);
    $h->restart(name => $res{name});

    say $_->{name} for $h->apps;

    $h->destroy(name => $res{name});


    warn 'Error:' . $h->error                     # Error: App not found.
      if not $h->destroy(name => $res{name});

    if (!$h->destroy(name => $res{name})) {
      my %err = $h->error;
      warn "$err{code}, $err{message}";           # 404, App not found.
    }

=head1 METHODS

=head2 new

    my $h = Net::Heroku->new(api_key => $api_key);
    - or -
    my $h = Net::Heroku->new(email => $email, password => $password);

Requires api key or user/pass. Returns Net::Heroku object.

=head2 apps

    my @apps = $h->apps;

Returns list of hash references with app information.

=head2 destroy

    my $bool = $h->destroy(name => $name);

Requires app name.  Destroys app.  Returns true if successful.

=head2 create

    my $app = $h->create;

Creates a Heroku app.  Accepts optional hash list as values, returns hash list.  Returns empty list on failure.

=head2 add_config

    my %config = $h->add_config(name => $name, config_key => $config_value);

Requires app name.  Adds config variables passed in hash list.  Returns hash config.

=head2 config

    my %config = $h->config(name => $name);

Requires app name.  Returns hash reference of config variables.

=head2 add_key

    my $bool = $h->add_key(key => ...);

Requires key.  Adds ssh public key.

=head2 keys

    my @keys = $h->keys;

Returns list of keys

=head2 remove_key

    my $bool = $h->remove_key(key_id => $key_id);

Requires id associated with key.  Removes key.

=head2 ps

    my @processes = $h->ps(name => $name);

Requires app name.  Returns list of dynos.

=head2 restart

    my $bool = $h->restart(name => $name);
    my $bool = $h->restart(name => $name, dyno => $dyno);

Requires app name.  Restarts app.  If dyno is supplied, only dyno is restarted.

=head2 stop

    my $bool = $h->stop(name => $name, dyno => $dyno);

Requires app name.  Stop app dyno.

=head2 releases

    my @releases = $h->releases(name => $name);
    my %release  = $h->releases(name => $name, release => $release);

Requires app name.  Returns list of hashrefs.
If release name specified, returns hash.

=head2 add_domain

    my $bool = $h->add_domain(name => $name, domain => $domain);

Requires app name.  Adds domain.

=head2 domains

    my @domains = $h->domains(name => $name);

Requires app name.  Returns list of hashrefs describing assigned domains.

=head2 remove_domain

    my $bool = $h->remove_domain(name => $name, domain => $domain);

Requires app name associated with domain.  Removes domain.

=head2 rollback

    my $bool = $h->rollback(name => $name, release => $release_id);

Rolls back to a specified release by id.

=head2 error

    my $message = $h->error;
    my %err     = $h->error;

In scalar context, returns error message from last request.

In list context, returns hash with keys: code, message.

If the last request was successful, returns empty list.

=head1 SEE ALSO

L<Mojo::UserAgent>, L<http://mojolicio.us/perldoc/Mojo/UserAgent#DEBUGGING>, L<https://api-docs.heroku.com/>

=head1 SOURCE

L<http://github.com/tempire/net-heroku>

=head1 VERSION

0.20

=head1 AUTHOR

Glen Hinkle C<tempire@cpan.org>

=head1 CONTRIBUTORS

Brian D. Foy

rage311

=cut
