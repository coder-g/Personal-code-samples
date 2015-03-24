package YouTube;

use warnings;
use strict;

use LWP::UserAgent;
use HTTP::Request;
use HTTP::Headers;
use HTTP::Message;
use XML::Simple;
use File::Slurp qw();
use Data::Dumper;

use HTML::Entities;
use JSON::WebToken;
use Encode qw();
use CHI;

=head1 NAME

A perl library for Google's YouTube API version3

=head1 VERSION

    Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    YouTube API


=head1 GLOBALS

    $api_key:  '';
    $agent:    '';

=cut

my $private_key_string ="";

my $debug = 1;
my $cache = CHI->new(
  driver => 'File',
  serializer=> 'Storable',
  root_dir => '/allafrica/CHI-file-cache',
  file_create_mode => 0664,
  dir_create_mode => 0775,
  namespace => 'google-api',
  on_set_error=> "warn",
  on_get_error=> "warn",
);

my $category    = 'News';
my $agent       = '';
my $region_code = 'US';
my $time = time;

$Data::Dumper::Indent = 2;
$Data::Dumper::Terse= 1;
my $retries = 0;

my $client_id = "";
my $client_secret = "";
my $server_key = "";
my $redirect_uri = "";
my $code = ""; #only redeemed once to obtain a token, token_secret and refresh_token.

my $auth_code_url = "https://accounts.google.com/o/oauth2/auth?". join("&",
  "client_id=$client_id",
  "redirect_uri=",
  "response_type=code",
  "scope=https://www.googleapis.com/auth/youtube%20https://www.googleapis.com/auth/youtube.upload",
  "access_type=offline"
);

my $ua = LWP::UserAgent->new( agent => $agent );

my %token = %{ $cache->get('access_token') || {} };

=head1 FUNCTIONS


=head2 authenticate

    Log on to youtube and get authentication token.
    The token is needed for all authenticated API requests

=cut


sub authenticate {
  my ( $refresh_token_flag ) = @_;

  unless( $refresh_token_flag ) {
    if ( scalar keys %token ) {
      if( $time > $token{expires_in_timestamp} && $retries < 1 ) {
        $retries = 1;
warn "Refreshing token stub 2" if $debug;
        return refresh_token( 1 );
      } elsif( $time < $token{expires_in_timestamp} ) {
        return $token{access_token};
      }
    } elsif( !$code ) {
      die "Follow this link to get an auth code: $auth_code_url\n";
    }
  }

  my $token_url = "https://accounts.google.com/o/oauth2/token";
  my $content_type = "application/x-www-form-urlencoded";
  my $content;

  if ( !$refresh_token_flag ) {
    $content = join("&",
      "code=$code",
      "client_id=$client_id",
      "client_secret=$client_secret",
      "grant_type=authorization_code",
      "redirect_uri=$redirect_uri",
    );
  } else {
    $content = join("&",
      "client_id=$client_id",
      "client_secret=$client_secret",
      "refresh_token=".$token{refresh_token},
      "grant_type=refresh_token",
    );
  }

  my $header = HTTP::Headers->new();
  $header->push_header('Content-Type' => $content_type);
  my $req = HTTP::Request->new( "POST", $token_url, $header, $content );
warn $req->as_string()."\n" if $debug;
  my $res = $ua->request($req);

  if ( $res->is_success ) {
warn $res->content."\n" if $debug;
    my $response_content = JSON::from_json($res->content);
    if( $refresh_token_flag ) {
      $token{access_token} = $response_content->{access_token};
    } else {
      %token = %{ $response_content };
    }
    $token{expires_in_timestamp} = $time + $response_content->{expires_in};
    $cache->set('access_token', \%token, "never" );
    
    return $token{access_token};
  } else {
    die $res->as_string."\nFollow this link to get an auth code: $auth_code_url\n";
  }
}


sub refresh_token {
  return authenticate( 1 );
}


my ( $pre, $post, $sent_pre, $sent_body, $sent_post, $fh, $data_filename );
my $READ_BUFF_SIZE = ( 1024 * 1024 );
sub send_this {

  if ( ! $sent_pre ) {
    $sent_pre++;
    return $pre;
  }

  if ( $sent_pre && ! $sent_body ) {
    unless ( $fh ) {
      open( $fh, "<$data_filename" ) || die $!;
    }

    my $buff;
    my $count = read( $fh, $buff, $READ_BUFF_SIZE );
#    warn $count;

    return $buff if $count;

    $sent_body++;
    close $fh;

  }

  if ( $sent_body && ! $sent_post ) {
    $sent_post++;
    return $post;
  }

  return '' if $sent_post;
}

sub upload_v2 {
  my ( $file, $filename, $title, $description, $keywords, $type, $private, $noembed ) = @_;
  die "USAGE: insufficient arguments supplied to upload()\n\n" .
        "eg:\tupload(<file>, <filename>, <title> <description>,
        <comma seperated keywords>, <file-type>,
        <optional: bool for private>, <optional: bool for noembed>)"
        unless ( $file && $filename && $title && $description && $keywords && $type );

  my $boundary  = "AllAfica-YouTubeAPI-Boundary";
  my $content_type  = "multipart/related; boundary=$boundary";

  my $url = "https://www.googleapis.com/upload/youtube/v3/videos";

  $url .= "?".join( "&",
    "part=snippet,status",
    "fields=id,snippet,fileDetails"
  );

  my $header = api_header();
  $header->push_header('Host' => 'www.googleapis.com');
  $header->push_header('Connection' => 'close');
  $header->push_header('Slug' => $filename);
  $header->push_header('Content-Type'  => $content_type );
  
  my $metadata = {
    snippet => {
      title => $title,
      description => $description,
      categoryId => youtube_category_id($region_code),
      tags => [ split(",", $keywords) ],
    },
  };
  $metadata->{status}->{privacyStatus} = "private" if $private == 1;
  $metadata->{status}->{embeddable} = $noembed if defined $noembed;

  my $req = HTTP::Request->new( "POST", $url, $header );

  my $content  = HTTP::Message->new( $header );
  $content->add_part( HTTP::Message->new( ['Content-Type' => 'application/json; charset=UTF-8'], JSON::to_json($metadata) ) );

  $content->add_part( HTTP::Message->new( ['Content-Type' => $type, 'Content-Transfer-Encoding' => 'binary'], "BINARY PLACEHOLDER" ) );
  $content->content() =~ m#^(.+)BINARY PLACEHOLDER(.+)$#s;
  ( $pre, $post ) = ( $1, $2 );

  $data_filename = $file;
  my $cl = length( $pre ) + ( -s $data_filename ) + length( $post );
  $req->push_header( 'Content-Length'  => $cl );
warn $req->as_string() if $debug;
  $req->content( \&send_this );

  my $res = $ua->request( $req );
  if ( $res->is_success) {
    return $res->content();
  } else {
    die $res->as_string;
  }
}



=head2 youtube_category_id

    method to retrieve and store the matching/relevant youtube categoryId for the value of $category. <region> is a string representing an ISO 3166-1 alpha-2 country code.
    usage: youtube_category_id(<region>)

=cut


sub youtube_category_id {
  my ( $region_code ) = @_;
  my %youtube_category = %{ $cache->get("youtube_category") || {} };
  unless( scalar keys %youtube_category ) {
    my $url = "https://www.googleapis.com/youtube/v3/videoCategories";
    $url .= "?".join("&",
      "part=snippet", "regionCode=$region_code", "key=$server_key"
    );
    my $req = HTTP::Request->new("GET", $url );
    my $res = $ua->request($req);
    if( $res->is_success) {
      my $content = JSON::from_json( $res->content );

      foreach my $item( @{ $content->{items} } ) {
        if( $item->{snippet}->{title} =~ m#$category#i ) {
          %youtube_category = (
            id => $item->{id},
            title => $item->{snippet}->{title},
          );
          $cache->set("youtube_category", \%youtube_category, "never");
          last;
        }
      }
      return $youtube_category{id} || die "No YouTube categoryId matches the category '$category' \n";
    } else {
      die $res->as_string();
    }
  }
  return $youtube_category{id};
}


=head2 update

    method to update a video on youtube
    usage: update(<yt_video_id>, <title>, <description>, <comma seperated keywords>, <private>, <noembed>);
    optional: <private>, <noembed>

=cut

sub update {
  my ( $id, $title, $description, $keywords, $private, $noembed ) = @_;
  die "USAGE: insufficient arguments supplied to update()"
    unless $id && $title && $description && $keywords;

  my $url = "https://www.googleapis.com/youtube/v3/videos";
  
  $url .= "?".join( "&",
    "part=snippet,status,contentDetails",
    "fields=id,snippet,fileDetails"
  );
  my $header = api_header();
  $header->push_header('Content-Type' => 'application/json');

  my $metadata = {
    snippet => {
      title => $title,
      description => $description,
      categoryId => youtube_category_id($region_code),
      tags => [ split(",", $keywords) ],
    },
    id => $id
  };
  $metadata->{status}->{privacyStatus} = "private" if $private == 1;
  $metadata->{status}->{embeddable} = $noembed if defined $noembed;

  my $req = HTTP::Request->new("PUT", $url, $header, JSON::to_json($metadata) );
warn $req->as_string()."\n" if $debug;
  my $res = $ua->request($req);
  if ( $res->is_success ) {
    return $res->content;
  } else {
    my $response_content = JSON::from_json( $res->content );
    if( $response_content->{error}->{code} =~ m#401#g ) {
      #if we ended up sending the PUT request with an expired access token
      if( $retries < 1 ) {
        $retries = 1;
warn "Refreshing token stub 1" if $debug;
        refresh_token(1);
        update_v2( $id, $title, $description, $keywords, $private, $noembed );
      }
    }
    die $res->as_string();
  }
}


=head1 UTILITY METHODS


=head2 api_header

    Prepare an HTTP::Headers object for API calls

=cut

sub api_header {
  my $token = authenticate();
  my $header = HTTP::Headers->new();
  $header->push_header( Authorization => 'Bearer ' . $token );
  return $header;
}


1; # End of YouTube
