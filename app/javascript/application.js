// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import 'darkModeManager';
import "@hotwired/turbo-rails";
import "controllers"; //pin of all from app/javascript/controllers
import "channels"; //pin of all from app/javascript/channels
import "turbo_stream_actions"; 
import "sl-tab-group_handler";

//shoelace (with Webawesome (WA) replacements)
import { setBasePath } from '@shoelace-style/shoelace/cdn/utilities/base-path';
setBasePath('https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.20.1/cdn/');
import "@shoelace-style/shoelace/icon"; // WA: icon
import "@shoelace-style/shoelace/icon-button"; // WA: MISSING (Use button+icon)
import "@shoelace-style/shoelace/button"; // WA: button
import "@shoelace-style/shoelace/spinner"; // WA: spinner
import "@shoelace-style/shoelace/progress-bar"; // WA: progress-bar
import "@shoelace-style/shoelace/tab-group"; // WA: tab-group
import "@shoelace-style/shoelace/tab"; // WA: tab
import "@shoelace-style/shoelace/tab-panel"; // WA: tab-panel
import "@shoelace-style/shoelace/alert"; // WA: MISSING - can use Callout to show the message itself but lacks toast functionality
import "@shoelace-style/shoelace/dropdown"; // WA: dropdown
import "@shoelace-style/shoelace/menu"; // WA: now part of dropdown
import "@shoelace-style/shoelace/menu-item"; // WA: moved to dropdown-item 
import "@shoelace-style/shoelace/input"; // WA: input
import "@shoelace-style/shoelace/dialog"; // WA: dialog
import "@shoelace-style/shoelace/textarea"; // WA: textarea
import "@shoelace-style/shoelace/details"; // WA: details
import "@shoelace-style/shoelace/copy-button"; // WA: copy-button
import "@shoelace-style/shoelace/tree"; // WA: tree
import "@shoelace-style/shoelace/tree-item"; // WA: tree-item
import "@shoelace-style/shoelace/drawer"; // WA: drawer

/*
//webawesome
import { setBasePath as setWebAwesomeBasePath } from '@awesome.me/webawesome/dist-cdn/webawesome';
setWebAwesomeBasePath('https://cdn.jsdelivr.net/npm/@awesome.me/webawesome@3.0.0/dist-cdn/');
import "@awesome.me/webawesome/icon";
import "@awesome.me/webawesome/button";
*/

import "katex";
import "katex-auto-render";
