#!/usr/bin/env perl

# vim: set ts=4 sw=4 tw=0:
# vim: set expandtab:

use strict;
use warnings;
use v5.32;

use Time::HiRes qw( time );

use lib './lib';
use Page qw( $page slurp update_feeds update_prs );

use Mojolicious::Lite -signatures;
use Mojo::IOLoop;
use Mojo::URL;
use Mojo::UserAgent;

my $TOKEN   = slurp('/run/secrets/nix_review');
my $refresh = 15 * 60;

my $ua = Mojo::UserAgent->new;
$ua->on(
    start => sub ( $ua, $tx ) {
        $tx->req->headers->header( "Authorization" => "Bearer ${TOKEN}" );
    }
);

Mojo::IOLoop->recurring(
    $refresh => sub ($loop) {
        update_feeds($ua);
        update_prs($ua);
    }
);

Mojo::IOLoop->recurring(
    1 => sub ($loop) {
        my $now = time();
        update_feeds($ua) if $page->{feedUpdated} - $now > $refresh;
        update_prs($ua)   if $page->{prsUpdated} - $now > $refresh;
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

get '/update_feeds' => sub ($c) {
    my $start = time();
    update_feeds($ua);
    my $end     = time();
    my $elapsed = sprintf( "%2f\n", $end - $start );
    $c->render( text => $elapsed );
};

get '/update_pr_info' => sub ($c) {
    my $start = time();
    update_prs($ua);
    my $end     = time();
    my $elapsed = sprintf( "%2f\n", $end - $start );
    $c->render( text => $elapsed );
};

app->start;

__DATA__
@@ index.html.ep
% layout 'default';
<h3><%= $page->{date} %>
<hr />
<div class="list">
  <div class="list_head">
    <span>NixOS Issues / PRs</span>
    <div class="list_head_right">
        <span onclick="updateGHFeeds(); return false">↻</span>
    </div>
  </div>
  <hr />
  <p><i>Updated <%= sprintf( "%.1f\n", (time() - $page->{feedUpdated}) / 60 ) %> minutes ago.</i></p>
  <ul>
  % foreach my $term (sort keys %{$page->{terms}}) {
    % if (scalar(@{$page->{terms}->{$term}}) > 0) {
    <li>
      <%= $term %>
      <ul>
      % foreach my $entry (sort { $b->{createdAt} cmp $a->{createdAt} } @{$page->{terms}->{$term}}) {
          <li>
            <a target="_blank" href="<%= $entry->{url} %>"><%= $entry->{title} %></a>
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
        <span>+</span>
        <span onclick="updatePRs(); return false">↻</span>
    </div>
  </div>
  <hr />
  <p><i>Updated <%= sprintf( "%.1f\n", (time() - $page->{prsUpdated}) / 60 ) %> minutes ago.</i></p>
  <ul>
  % foreach my $pr (sort sort { $b->{repo} cmp $a->{repo} } @{$page->{pullrequests}}) {
    <li>
      <a target="_blank" href="https://github.com/<%= $pr->{repo} %>/pull/<%= $pr->{number} %>">
        <%= $pr->{repo} %>: <%= $pr->{number} %>
      </a>
      % if ($pr->{repo} eq "NixOS/nixpkgs" or scalar keys %{ $pr->{info} } > 0) {
        <ul>
        % if ($pr->{repo} eq "NixOS/nixpkgs") {
          % if ( scalar keys %{ $pr->{info} } > 0) {
            % foreach my $k (keys %{ $pr->{info} }) {
              % if ( $k eq "commit" ) {
                % foreach my $b (sort @{ $pr->{info}->{branches} } ) {
                  <li><%= $b %></li>
                % }
              % }
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
        <span>+</span>
    </div>
  </div>
  <hr />
  <ul>
  % foreach my $link (sort { $a->{name} cmp $b->{name} } @{$page->{links}}) {
    <li><a target="_blank" href="<%= $link->{url} %>"><%= $link->{name} %></a></li>
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

.list_head_right {
    cursor: pointer;
}

.list p {
    padding-left: 10px;
}

@@ main.js.ep
function updatePRs() {
    const req = new Request('/update_pr_info');
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
function updateGHFeeds() {
    const req = new Request('/update_feeds');
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
