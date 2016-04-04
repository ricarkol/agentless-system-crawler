/**
 * Created by sastryduri on 4/23/15.
 */
angular.module('categories.bookmarks.timeline', [
    'tm.models.bookmarks'
])
    .config(function($stateProvider){
    })
    .controller('BookmarksTimelineCtrl', function($stateParams){
        var bookmarksTimelineCtrl = this;
        bookmarksTimelineCtrl.ctrl = "RealBookmarksTimelineCtrl";

    })
;
