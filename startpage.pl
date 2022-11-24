#!/usr/bin/env perl

# vim: set ts=4 sw=4 tw=0:
# vim: set expandtab:

use strict;
use warnings;
use v5.32;
use Data::Dumper;

my $VERSION = 'v0.0.1';

use Time::HiRes qw( time );

use FindBin qw($Bin);
use lib "$Bin/lib";
use lib "$Bin/../lib/perl5/site_perl/";

use Page
  qw( $page slurp update_gh_feed update_prs gh_ignore_number cache_logos $sql $ua );

use Mojolicious::Lite -signatures;
use Mojo::IOLoop;
use Mojo::URL;

my $db = $sql->db;

my $TOKEN   = slurp('/run/secrets/nix_review');
my $refresh = 15 * 60;

$ua->on(
    start => sub ( $ua, $tx ) {
        $tx->req->headers->header( "Authorization" => "Bearer ${TOKEN}" );
    }
);

Mojo::IOLoop->recurring(
    $refresh => sub ($loop) {
        update_gh_feed($ua);
        update_prs($ua);
    }
);

Mojo::IOLoop->recurring(
    1 => sub ($loop) {
        my $now = time;
        update_gh_feed($ua) if $page->{feedUpdated} - $now > $refresh;
        update_prs($ua)     if $page->{prsUpdated} - $now > $refresh;
    }
);

get '/' => sub ($c) {
    $page->{date} = localtime;

    $c->stash( page => $page );
    $c->render( template => 'index' );
};

get '/style.css' => sub ($c) {
    $c->render( template => 'style', format => 'css' );
};
get '/main.js' => sub ($c) {
    $c->render( template => 'main', format => 'js' );
};

get '/update' => sub ($c) {
    my $start = time;
    update_gh_feed($ua);
    update_prs($ua);
    my $end     = time;
    my $elapsed = sprintf( "%2f\n", $end - $start );
    $c->render( text => $elapsed );
};

get '/update_gh_feed' => sub ($c) {
    my $start = time;
    update_gh_feed($ua);
    my $end     = time;
    my $elapsed = sprintf( "%2f\n", $end - $start );
    $c->render( text => $elapsed );
};

get '/update_pr_info' => sub ($c) {
    my $start = time;
    update_prs($ua);
    my $end     = time;
    my $elapsed = sprintf( "%2f\n", $end - $start );
    $c->render( text => $elapsed );
};

put '/add_link' => sub ($c) {
    my $data = $c->req->json;
    my $result =
      $db->query( 'insert into links (name, url, logo) values (?, ?, ?)',
        $data->{name}, $data->{url}, $data->{logo} );

    $page->{links} = $db->select('links')->hashes;

    cache_logos($ua);

    $c->render( json => $result );
};

put '/rm_track' => sub ($c) {
    my $data = $c->req->json;
    my $result =
      $db->query( 'delete from pull_requests where id = ?', $data->{id} );

    $page->{pullrequests} = $db->select('pull_requests')->hashes;
    for my $pr ( @{ $page->{pullrequests} } ) {
        $pr->{branches} = [];
    }

    $c->render( json => $result );
};

put '/add_track' => sub ($c) {
    my $data = $c->req->json;
    my $result =
      $db->query(
'insert into pull_requests (number, repo, description) values (?, ?, ?)',
        $data->{number}, $data->{repo}, $data->{description} );

    # TODO: make a function
    $page->{pullrequests} = $db->select('pull_requests')->hashes;
    for my $pr ( @{ $page->{pullrequests} } ) {
        $pr->{branches} = [];
    }

    $c->render( json => $result );
};

put '/add_ignore' => sub ($c) {
    my $data   = $c->req->json;
    my $result = $db->query( 'insert into pr_ignores (pr, repo) values (?, ?)',
        $data->{number}, $data->{repo} );

    $page->{links} = $db->select('links')->hashes;

    # TODO: make a function
    my $ignores = $db->query('select * from pr_ignores');
    while ( my $next = $ignores->hash ) {
        my $repo = $next->{repo};
        my $pr   = $next->{pr};
        $page->{ignores}->{$repo} = [] unless defined $page->{ignores}->{$repo};
        push @{ $page->{ignores}->{$repo} }, $pr;
    }

    # TODO: remove updated ignores from pullrequests

    $c->render( json => $result );
};

app->start;

__DATA__
@@ index.html.ep
% layout 'default';
<h3><%= $page->{date} %>
<br />
<span onclick="update('/update'); return false">↻</span><br />
Queries left: <%= $page->{rateLimit}->{remaining} %>
<hr />
<div class="list">
  <div class="list_head">
    <span>NixOS Issues / PRs</span>
    <div class="list_head_right">
        <span onclick="updateGHFeeds(); return false">↻</span>
    </div>
  </div>
  <hr />
  <p>
    <i>Updated <%= sprintf( "%.1f\n", (time - $page->{feedUpdated}) / 60 ) %> minutes ago.</i>
  </p>
  <ul>
  % foreach my $term (sort keys %{$page->{terms}}) {
    % if (scalar(@{$page->{terms}->{$term}}) > 0) {
    <li>
      <%= $term %>
      <ul>
      % foreach my $entry (sort { $b->{createdAt} cmp $a->{createdAt} } @{$page->{terms}->{$term}}) {
          <li>
            <span onclick="trackNixOS('<%= $entry->{number} %>', '<%= $entry->{title} %>'); return false;">+</span>
            <span onclick="ignorePR('<%= $entry->{number} %>', 'NixOS/nixpkgs')">-</span>
            <%= $entry->{number} %> : <a target="_blank" href="<%= $entry->{url} %>"><%= $entry->{title} %></a>
          </li>
      % }
      </ul>
    </li>
    % }
  % }
  </ul>
</div>
<div class="list">
  <div class="list_head">
    <span>Pull Request Tracker</span>
    <div class="list_head_right">
        <span id="addTrack">+</span>
        <dialog id="trackDialog">
          <form id="trackForm" method="dialog">
            <label>PR number <input type="text" name="number" /></label><br />
            <label>Repo <input type="text" name="repo" /></label><br />
            <label>Description <input type="text" name="description" /></label><br />
            <div>
              <button id="cancelTrack" value="cancel">Cancel</button>
              <button id="submitTrack">Add</button>
            </div>
          </form>
        </dialog>
        <span onclick="updatePRs(); return false">↻</span>
    </div>
  </div>
  <hr />
  <p><i>Updated <%= sprintf( "%.1f\n", (time - $page->{prsUpdated}) / 60 ) %> minutes ago.</i></p>
  <ul>
  % foreach my $pr (sort sort { $b->{repo} cmp $a->{repo} } @{$page->{pullrequests}}) {
    <li>
      <span onclick="editTracked('<%= $pr->{number} %>'); return false;">✎</span>
      <span onclick="rmFromTracker('<%= $pr->{id} %>')">X</span>
      <%= $pr->{repo} . " : " . $pr->{description} || "" %> : 
      <a target="_blank" href="https://github.com/<%= $pr->{repo} %>/pull/<%= $pr->{number} %>">
        <%= $pr->{number} %>
      </a>
      % if ($pr->{repo} eq "NixOS/nixpkgs" or scalar keys %{ $pr } > 0) {
        <ul>
        % if ($pr->{repo} eq "NixOS/nixpkgs") {
              % if ( $pr->{commitid} ) {
                % foreach my $b (sort @{ $pr->{branches} } ) {
                  <li><%= $b %></li>
                % }
              % }
        % }
        </ul>
      % }
    </li>
  % }
  </ul>
</div>
<div class="list">
  <div class="list_head">
    <span>Links</span>
    <div class="list_head_right">
        <span id="addLink">+</span>
        <dialog id="linkDialog">
          <form id="linkForm" method="dialog">
            <label>Name: <input type="text" name="name" /></label><br />
            <label>URL: <input type="text" name="url" /></label><br />
            <label>Logo: <input type="text" name="logo" /></label><br />
            <div>
              <button id="cancelLink" value="cancel">Cancel</button>
              <button id="submitLink">Add</button>
            </div>
          </form>
        </dialog>
    </div>
  </div>
  <hr />
  <ul class="icons">
  % foreach my $link (sort { $a->{name} cmp $b->{name} } @{$page->{links}}) {
    <a href="<%= $link->{url} %>">
      <li>
        <img src="data:<%= $link->{logo_content_type} %>;base64,<%= $link->{cached_logo} %>" /><br />
        <%= $link->{name} %>
      </li>
    </a>
  % }
  </ul>
</div>

@@ layouts/default.html.ep
<!doctype html>
<html class="no-js" lang="">
  <head>
    <title><%= $page->{title} %></title>
    <meta charset="utf-8">
    <meta http-equiv="x-ua-compatible" content="ie=edge">
    <meta name="description" content="<%= $page->{descr} %>">
    <link rel="stylesheet" href="/style.css">
  </head>
  <body>
    <div class="results">
      <%== content %>
    </div>
  </body>
  <script type="text/javascript" src="/main.js"></script>
</html>

@@ style.css.ep
body {
  background-color: #ffffea;
  text-align: center;
  font-family: Avenir, 'Open Sans', sans-serif;
}

.results {
    width: 98%;
    border: 1px solid black;
    overflow: hidden;
    padding: 10px;
    border-radius: 10px;
}

.list {
    width: 30%;
    float: left;
    border: 1px solid black;
    text-align: left;
    padding-left: 10px;
    padding-right 10px;
    margin: 10px;
    border-radius: 10px;
	box-shadow: 2px 2px 2px black;
}

.list_head {
    //background-color: #eaeaff;
    padding-top: 5px;
}

.list_head_right {
    float: right;
    padding-right: 10px;
}

ul span {
    cursor: pointer;
}

.list_head_right {
    cursor: pointer;
}

.list p {
    padding-left: 10px;
}

.icons li {
    float: left;
    padding: 10px;
    margin: 10px;
    width: 130px;
    height: 130px;
    border-radius: 10px;
    border: 1px solid black;
    list-style-type: none;
    text-align: center;
}

.icons li img {
    width: 50px;
    hight: 50px;
}

@@ main.js.ep

function update(item) {
    const req = new Request(item);
    fetch(req)
     .then((response) => {
       if (!response.ok) {
         throw new Error(`HTTP error! Status: ${response.status}`);
       }

       return response;
     })
     .then((response) => {
       window.location.reload(false);
     });
}

function updatePRs() {
    update('/update_pr_info');
}
function updateGHFeeds() {
    update('/update_gh_feed');
}

function makeSubmitter(add, dialog, submit, form, url) {
    const addLink = document.getElementById(add);
    const linkDialog = document.getElementById(dialog);
    const submitLink = document.getElementById(submit);
    const linkForm = document.getElementById(form);

    addLink.addEventListener('click', () => {
        linkDialog.showModal();
    });
    submitLink.addEventListener('click', () => {
        const data = Object.fromEntries(new FormData(linkForm).entries());
        fetch(url, {
                method: 'PUT',
                headers: {
                    'Accept': 'application/json',
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(data),
        });
    });
}

function trackNixOS(number, description) {
    const data = {
        number: number,
        repo: "NixOS/nixpkgs",
        description: description
    };
    fetch('/add_track', {
            method: 'PUT',
            headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(data),
    });
}

function ignorePR(number, repo) {
    const data = {
        number: number,
        repo: repo,
    };
    fetch('/add_ignore', {
            method: 'PUT',
            headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(data),
    });
}
function rmFromTracker(pr_id) {
    const data = {
        id: pr_id,
    };
    fetch('/rm_track', {
            method: 'PUT',
            headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
            },
            body: JSON.stringify(data),
    });
}

makeSubmitter('addLink', 'linkDialog', 'submitLink', 'linkForm', '/add_link');
makeSubmitter('addTrack', 'trackDialog', 'submitTrack', 'trackForm', '/add_track');
