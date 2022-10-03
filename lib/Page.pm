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
use Git;

our @ISA       = qw( Exporter );
our @EXPORT_OK = qw( $page slurp update_feeds update_prs );

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

$ENV{"GIT_CONFIG_SYSTEM"} = "";        # Ignore insteadOf rules
$ENV{"HOME"}              = "/tmp";    # Ignore ~/.netrc
Git::command( 'clone', 'https://github.com/nixos/nixpkgs', '/tmp/nixpkgs' )
  if !-e '/tmp/nixpkgs';
my $repo = Git->repository( Directory => '/tmp/nixpkgs' );

our $page = {
    title        => "startpage",
    descr        => "a page to start with",
    feedUpdated  => time(),
    prsUpdated   => time(),
    pullrequests => [
        {
            repo   => "NixOS/nixpkgs",
            number => 193662,
            info   => {
                commit   => '42115269e7dfeedebc38be3e45d652de18414bf9',
                branches => []
            }
        },
        {
            repo   => "NixOS/nixpkgs",
            number => 193186,
            info   => {}
        },
        {
            repo   => "newrelic/go-agent",
            number => 567,
            info   => {
                thing => "stuff"
            }
        }
    ],
    links => [
        {
            name => "Bold Daemon Stats",
            url  =>
"https://graph.tapenet.org/d/lawL-fMVz/bold-daemon?orgId=1&refresh=5s"
        },
        {
            name => "Books",
            url  => "https://books.bold.daemon"
        },
        {
            name => "LibReddit",
            url  => "https://reddit.bold.daemon"
        },
        {
            name => "MammothCirc.us",
            url  => "https://mammothcirc.us"
        }
    ],

    terms => {
        tailscale         => [],
        "matrix-synapse"  => [],
        nheko             => [],
        obsidian          => [],
        restic            => [],
        "element-desktop" => [],
        "tidal-hifi"      => []
    }
};

sub slurp {
    my $f = shift;

    open my $fh, '<', $f or die;

    local $/ = undef;

    my $d = <$fh>;
    close $fh;

    chomp $d;
    return $d;
}

sub check_nixpkg_branches {
    my $commit = shift;

    my $branches = $repo->command( 'branch', '-r', '--contains', $commit );

    my $list = [];
    foreach my $b ( split( '\n', $branches ) ) {
        $b =~ s/^\s+origin\///g;
        push( @$list, $b ) if $b =~ m/unstable/;
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

sub update_feeds {
    my $ua = shift;
    foreach my $term ( sort keys %{ $page->{terms} } ) {
        my $q  = sprintf( $termQL, $term );
        my $tx = $ua->post(
            'https://api.github.com/graphql' => json => { query => $q } );
        my $j = from_json $tx->result->body;
        $page->{terms}->{$term} = [];
        foreach my $node ( @{ $j->{data}->{search}->{edges} } ) {
            push @{ $page->{terms}->{$term} }, $node->{node};
        }
        Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
    }
    $page->{feedUpdated} = time();
}

1;
