# vim: set ts=4 sw=4 tw=0:
# vim: set expandtab:

package Page;

use 5.10.0;
use feature 'signatures';
use strict;
use warnings;
use Data::Dumper;

use Exporter 'import';

use JSON qw( from_json );
use MIME::Base64 qw( encode_base64 );
use Git;

use Mojo::SQLite;
use Mojo::UserAgent;

our $sql = Mojo::SQLite->new('sqlite:startpage.db');
our $ua  = Mojo::UserAgent->new;
$sql->migrations->name('startpage_init')->from_string(<<EOF)->migrate;
-- 1 up
create table watch_items (id integer primary key autoincrement, name text not null unique, descr text);
create table pr_ignores (id integer primary key autoincrement, pr integer not null, repo text not null, unique(pr, repo)); 
create table links (id integer primary key autoincrement, url text not null unique, name text not null, logo text);
create table pull_requests (
    id integer primary key autoincrement,
    number integer not null unique,
    repo text not null,
    description text, commitid text);
-- 1 down
drop table watch_items;
drop table pr_ignores;
drop table links;
drop table pull_requests;
EOF

$sql->migrations->name('icon_cache')->from_string(<<EOF)->migrate;
-- 2 up
create table icons (id integer primary key autoincrement, url text not null unique, content_type text not null, data blob not null);
-- 1 down
drop table icons;
EOF

my $db = $sql->db;

$sql->migrations->migrate;

our @ISA = qw( Exporter );
our @EXPORT_OK =
  qw( $page slurp update_gh_feed update_prs gh_ignore_number cache_logos $sql $ua );

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
      rateLimit {
        remaining
        resetAt
      }
    }
};

our $page = {
    descr        => "a page to start with",
    title        => "startpage",
    links        => [],
    ignores      => {},
    pullrequests => []
};

$page->{links} = $db->select('links')->hashes;
cache_logos($ua);
$page->{pullrequests} = $db->select('pull_requests')->hashes;

my $terms = $db->query('select * from watch_items');
while ( my $next = $terms->hash ) {
    $page->{terms}->{ $next->{name} } = [];
}

my $ignores = $db->query('select * from pr_ignores');
while ( my $next = $ignores->hash ) {
    my $repo = $next->{repo};
    my $pr   = $next->{pr};
    $page->{ignores}->{$repo} = [] unless defined $page->{ignores}->{$repo};
    push @{ $page->{ignores}->{$repo} }, $pr;
}

for my $pr ( @{ $page->{pullrequests} } ) {
    $pr->{branches} = [];
}

$page->{prsUpdated}  = time();
$page->{feedUpdated} = time();
$page->{rateLimit}   = {};

my $repo_dir = "/home/qbit/startpage_nixpkgs";
$ENV{"GIT_CONFIG_SYSTEM"} = "";        # Ignore insteadOf rules
$ENV{"HOME"}              = "/tmp";    # Ignore ~/.netrc
Git::command( 'clone', 'https://github.com/nixos/nixpkgs', $repo_dir )
  if !-e $repo_dir;
my $repo = Git->repository( Directory => $repo_dir );

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
    print "Updating prs...  ";

    $repo->command('fetch');

    foreach my $pr ( sort @{ $page->{pullrequests} } ) {
        if ( defined $pr->{commitid} ) {
            $pr->{branches} =
              check_nixpkg_branches( $pr->{commitid} );
        }
    }
    $page->{prsUpdated} = time();
}

sub cache_logos {
    my $ua = shift;
    foreach my $link ( sort @{ $page->{links} } ) {

        # TODO: cache loaded info into icons table
        my $tx = $ua->get( $link->{logo} );
        $link->{cached_logo}       = encode_base64( $tx->result->body );
        $link->{logo_content_type} = "image/png";
        $link->{logo_content_type} = "image/svg+xml"
          if $link->{logo} =~ m/svg$/;
    }
}

sub update_gh_feed {
    my $ua = shift;
    print "Updating GitHub feed...   ";
    foreach my $term ( sort keys %{ $page->{terms} } ) {
        my $q  = sprintf( $termQL, $term );
        my $tx = $ua->post(
            'https://api.github.com/graphql' => json => { query => $q } );
        my $j = from_json $tx->result->body;
        $page->{terms}->{$term} = [];
        foreach my $node ( @{ $j->{data}->{search}->{edges} } ) {
            my $repo = $node->{node}->{repository}->{nameWithOwner};
            if ( !gh_ignore_number( $node->{node}->{number}, $repo ) ) {
                push( @{ $page->{terms}->{$term} }, $node->{node} );
            }
        }
        $page->{rateLimit} = $j->{data}->{rateLimit}
          if defined $j->{data}->{rateLimit}->{remaining};
        Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
    }
    $page->{feedUpdated} = time();
}

1;
