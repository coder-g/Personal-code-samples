package APIS::Facebook;

use warnings;
use strict;
use Facebook::OpenGraph qw();
use Data::Dumper;
use LWP::UserAgent;
use XML::Comma;
use CHI;
use APIS::DocGroup;

=head1 NAME

Facebook - A thin custom wrapper to Facebook::OpenGraph. Share links and update facebook statuses

=head1 VERSION

Version 0.01

=cut

our $VERSION = "0.01";

=head1 SYNOPSIS

Custom API to Facebook

    use APIS::Facebook;

    APIS::Facebook::update_status( language => "en", author_key=> $author_key, message => $caption, link=> $link );

=head1 GLOBALS

my $pages = {
  en => "",
  fr => "",
};

my $app_id => "",
my $app_secret => "",

=cut

my $cache = CHI->new(
  driver => 'File',
  serializer=> 'Storable',
  root_dir => '/CHI-file-cache',
  file_create_mode => 0664,
  dir_create_mode => 0775,
  namespace => 'facebook',
  on_set_error=> "warn",
  on_get_error=> "warn",
);
my $wu_index = XML::Comma::Def->WebUser->get_index("main");

my $pages = {
  en => "",
  fr => "",
};
my $app_id = "";
my $agent = "";

my $app_secret = "";
my $debug = 1;

$Data::Dumper::Indent = 2;
$Data::Dumper::Terse= 1;

my %tracking_indices = (
  'temp' => XML::Comma::Def->Tracking->get_index( "temp" ),
  'main' => XML::Comma::Def->Tracking->get_index( "main" ),
);
my $ua = Furl::HTTP->new(
  ssl_opts => {
    SSL_verify_mode => 'SSL_VERIFY_PEER',
  },
);

=head1 FUNCTIONS

=head2 get_long_lived_user_access_token

    Exchanges a short-lived user_access_token for a long-lived user_access_token (usually one month)
    - usage: get_long_lived_user_access_token(token=>$token, language => 'en')

=cut

sub get_long_lived_user_access_token {
  my %args = @_;

  die "USAGE: get_long_lived_user_access_token(token => \$short_lived_token, language=>(en|fr))"
    unless defined $args{token} && defined $args{language} && $args{language} =~ m#^(en|fr)$#;
  my $ua = LWP::UserAgent->new( agent => $agent, ssl_opts => { verify_hostname => 0 } );
  my $url = "https://graph.facebook.com/oauth/access_token";

  my $headers = HTTP::Headers->new();
  $headers->push_header('Content-Type' => 'application/x-www-form-urlencoded');

  my @content = ( "grant_type=fb_exchange_token",
    "client_id=$app_id",
    "client_secret=$app_secret",
    "fb_exchange_token=$args{token}",
  );
  $url .= '?'.join( '&', @content );

  my $req = HTTP::Request->new( "GET", $url, $headers );
  my $res = $ua->request( $req );
  if ( $res->is_success ) {
    my $content = $res->content();
    my ($token, $expiry);
    if ( $content =~ m#\&# ) {
      ( $token, $expiry ) = split('&', $content);
      $expiry =~ s#expires=##;
    } else {
      $token = $content;
    }
    $token =~ s#access_token=##;

warn "user token:$token\n" if $debug;
    return $token;
  } else {
    die "ERROR\n".$res->as_string();
  }
}

=head2 get_page_access_token

    Exchanges a user_access_token for a page_access_token.
    -The user_access_token must be long-lived (1 month) to get a long-lived page_access_token( non-expiring).
    -usage: get_page_access_token(token=>$token)

=cut

sub get_page_access_token {
  my %args = @_;

  die "USAGE: get_page_access_token(token => \$token)"
    unless defined $args{token};

  my $fb = Facebook::OpenGraph->new(+{
    app_id => $app_id,
    secret => $app_secret,
    access_token => $args{token},
    ua => $ua,
  });
  my $response = eval{ $fb->get('me/accounts') };
  if ( my $error = $@) {
    die "Error getting page access token: '$error'\n";
  }
  my $token = $response->{data}[0]->{access_token} || "";
  if ( !$token ) {
warn "No page token returned. Has this user been added to the editors list on the page?\n" if $debug;
warn "response:".Data::Dumper::Dumper( $response );
    die "Could not get user token from Facebook";
  }

warn "page token:$token\n" if $debug;
  return $token;
}


=head2 authenticate

    Log on to EN or FR Facebook accounts and get auth object - usage: authenticate(language => 'en', author_key=>$author_key)

=cut

sub authenticate {
  my %args = @_;
  die "USAGE: authenticate(author_key=>\$author_key, langauge => 'en|fr')"
    unless defined $args{author_key} && defined $args{language} && $args{language} =~ m#^(en|fr)$#;

  my $page_access_token;
  if ( $args{retrieve_token_from_chi} ) {
    $page_access_token = $cache->get($args{author_key}) || "";
  } else {
    my $doc_id = (XML::Comma::Storage::Util->split_key( $args{author_key} ))[2];
    my $single = eval { $wu_index->single( where_clause => qq[doc_id="$doc_id"] ) };
    my $doc = $single->read_doc();
    if ( my $error = $@ ) {
      die "$error";
    }

    $page_access_token = $doc->get_value_for_service("facebook","oauth_token");
  }
  die "No access token found for '$args{author_key}'" unless $page_access_token;

  my $language  = $args{language};

  my $fb = Facebook::OpenGraph->new(+{
    app_id => $app_id,
    secret => $app_secret,
    access_token => $page_access_token,
    ua => $ua,
  });

warn "\nSet token:".$fb->access_token."\n" if $debug;
  return $fb;
}

=head2 update_status

    Send status update to Facebook page
    - usage: update_status(language => 'en', message => $status )
             update_status(language => 'en', message => $caption, image=> $image_link )
             update_status(language => 'en', message => $caption, link=> $link_to_share )
             update_status(language => 'en', message=>"scheduled post", scheduled_publish_time=>"1407140781", published=>"false")

=cut

sub update_status {
  my %args = @_;

  my $usage = "USAGE: update_status(author_key=>\$author_key, language => (en|fr), message => 'Some text to update')";
  die $usage unless defined $args{author_key} && defined $args{language} && $args{language} =~ m#^(en|fr)$#;

  my $fb = authenticate( author_key=> $args{author_key}, language => $args{language}, retrieve_token_from_chi => $args{retrieve_token_from_chi} );

  my %fields;
  foreach my $field( qw(message scheduled_publish_time no_story published link) ) {
    $fields{$field} = $args{$field} if $args{$field};
  }

  my @endpoint = ($pages->{$args{language}});
  if ( $args{image} ) {
    push @endpoint, "/photos";
    $fields{url} = $args{image};
  } else {
    push @endpoint, "/feed";
  }

  my $response = $fb->request( "POST", join( '', @endpoint ), \%fields );

  return $response;
}

=head2 check_facebook_status

    Check if a given doc_key has been 'facebooked' - usage check_facebook_status(doc_key => $doc_key)
    returns the doc_key of the tracking doc associated with a previous facebook status action or undef

=cut

sub check_facebook_status {
  my %args = @_;

  die 'USAGE: check_facebook_status(doc_key => $doc_key)'
  unless defined $args{doc_key};

  my $doc_key = $args{doc_key};
  my $where_clause = qq[item_key="$doc_key" AND action="facebook status"];
  foreach my $index_name ( qw(temp main) ) {
    my $single = $tracking_indices{$index_name}->single(where_clause => $where_clause);
    return $single->doc_key if $single;
  }
}

1;

=head1 AUTHOR

Francis Njiru, C<< <fnjiru at allafrica.com> >>


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc APIS::Facebook



=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

Copyright 2014 Francis Njiru.

This program is free software; you can redistribute it and/or modify it
under the terms of either: the GNU General Public License as published
by the Free Software Foundation; or the Artistic License.

See http://dev.perl.org/licenses/ for more information.


=cut

1; # End of APIS::Facebook