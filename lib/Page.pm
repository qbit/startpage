# vim: set ts=4 sw=4 tw=0:
# vim: set expandtab:

package Page;

use 5.10.0;
use feature 'signatures';
use feature 'say';
use strict;
use warnings;
use Data::Dumper;

use Exporter 'import';

use JSON qw( from_json );
use MIME::Base64 qw( encode_base64 );
use Git;

our @ISA = qw( Exporter );
our @EXPORT_OK =
  qw( $page slurp update_gh_feed update_prs gh_ignore_number cache_logos );

my $termQL = q{
    {
      search(query: "is:open is:public archived:false repo:nixos/nixpkgs in:title %s", type: ISSUE, first: 10) {
        issueCount
        edges {
          node {
            ... on Issue {
              number
              title
              url
              repository {
                nameWithOwner
              }
              createdAt
            }
            ... on PullRequest {
              number
              title
              repository {
                nameWithOwner
              }
              createdAt
              url
            }
          }
        }
      }
    }
};

our $page = {};
open my $fh, '<', "$ENV{HOME}/.startpage" or die "Can't open file $!";
my $page_data = do { local $/; <$fh> };
close $fh;

$page                = from_json $page_data;
$page->{prsUpdated}  = time();
$page->{feedUpdated} = time();

$ENV{"GIT_CONFIG_SYSTEM"} = "";        # Ignore insteadOf rules
$ENV{"HOME"}              = "/tmp";    # Ignore ~/.netrc
Git::command( 'clone', 'https://github.com/nixos/nixpkgs', '/tmp/nixpkgs' )
  if !-e '/tmp/nixpkgs';
my $repo = Git->repository( Directory => '/tmp/nixpkgs' );

sub slurp {
    my $f = shift;

    open my $fh, '<', $f or die;

    local $/ = undef;

    my $d = <$fh>;
    close $fh;

    chomp $d;
    return $d;
}

sub gh_ignore_number {
    my ( $number, $repo ) = @_;

    return 0 unless defined $page->{ignores}->{$repo};
    return 1 if ( grep /$number/, @{ $page->{ignores}->{$repo} } );

    return 0;
}

sub check_nixpkg_branches {
    my $commit = shift;
    my $list   = [];

    return $list if $commit eq "";

    my $branches = $repo->command( 'branch', '-r', '--contains', $commit );

    foreach my $b ( split( '\n', $branches ) ) {
        $b =~ s/^\s+origin\///g;
        push( @$list, $b ) if $b =~ m/nixos|nixpkgs|staging|master/;
    }

    return $list;
}

sub update_prs {
    my $ua = shift;

    $repo->command('fetch');

    foreach my $pr ( sort @{ $page->{pullrequests} } ) {
        if ( defined $pr->{info}->{commit} ) {
            $pr->{info}->{branches} =
              check_nixpkg_branches( $pr->{info}->{commit} );
        }
    }
    $page->{prsUpdated} = time();
}

sub cache_logos {
    my $ua = shift;
    foreach my $link ( sort @{ $page->{links} } ) {
        my $tx = $ua->get( $link->{logo} );
        $link->{cached_logo}       = encode_base64( $tx->result->body );
        $link->{logo_content_type} = "image/png";
        $link->{logo_content_type} = "image/svg+xml"
          if $link->{logo} =~ m/svg$/;
    }
}

sub update_gh_feed {
    my $ua = shift;
    foreach my $term ( sort keys %{ $page->{terms} } ) {
        my $q  = sprintf( $termQL, $term );
        my $tx = $ua->post(
            'https://api.github.com/graphql' => json => { query => $q } );
        my $j = from_json $tx->result->body;
        $page->{terms}->{$term} = [];
        foreach my $node ( @{ $j->{data}->{search}->{edges} } ) {
            my $repo = $node->{node}->{repository}->{nameWithOwner};
            if ( gh_ignore_number( $node->{node}->{number}, $repo ) ) {
                say "ignoring $repo / $node->{node}->{number}";
            }
            else {
                push( @{ $page->{terms}->{$term} }, $node->{node} );
            }
        }
        Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
    }
    $page->{feedUpdated} = time();
}

1;
