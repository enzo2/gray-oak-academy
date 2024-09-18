// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import 'darkModeManager';
import "@hotwired/turbo-rails";
import "controllers"; //pin of all from app/javascript/controllers
import "channels" //pin of all from app/javascript/channels

//shoelace
import { setBasePath } from '@shoelace-style/shoelace/dist/utilities/base-path';
setBasePath('https://cdn.jsdelivr.net/npm/@shoelace-style/shoelace@2.16.0/dist/');
import "@shoelace-style/shoelace/icon";
import "@shoelace-style/shoelace/icon-button";
import "@shoelace-style/shoelace/button";
import "@shoelace-style/shoelace/input";
import "@shoelace-style/shoelace/dropdown";
import "@shoelace-style/shoelace/spinner";
//import "@shoelace-style/shoelace/checkbox";
//import "@shoelace-style/shoelace/dialog";
//import "@shoelace-style/shoelace/textarea";

