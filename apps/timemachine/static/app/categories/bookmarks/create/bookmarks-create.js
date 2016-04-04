angular.module('categories.bookmarks.create', [
    'tm.models.bookmarks'
])
    .config(function($stateProvider){

        $stateProvider.state('tm.categories.bookmarks.create', {
            url:"/create",
            views: {
                'categories@':{
                    controller: 'BookmarksOptionsCtrl as bookmarksOptionsCtrl',
                    templateUrl: 'static/app/categories/bookmarks/options.tmpl.html'
                },
                'summary@':{
                    controller: 'CreateBookmarkCtrl as createBookmarkCtrl',
                    templateUrl: 'static/app/categories/bookmarks/create/bookmarks-create.tmpl.html'
                }
                //'timeline@':{
                //    controller: 'BookmarksTimelineCtrl as bookmarksTimelineCtrl',
                //    templateUrl: 'static/app/categories/bookmarks/timeline.tmpl.html'
                //}
            }
        })
    }).controller('CreateBookmarkCtrl', function BookmarksCreateCtrl(){
        var createBookmarkCtrl = this;

        createBookmarkCtrl.ctrl = 'CreateControl';
        createBookmarkCtrl.newBookmark = {};
        createBookmarkCtrl.createBookmark = createBookmark;
        createBookmarkCtrl.cancelCreating = cancelCreating;


        function createBookmark (bookmark){
            var msg = 'create tags:' + bookmark.tags +'; namespaces:' + bookmark.namespaces;
            alert(msg);
        };

        function cancelCreating (){
            alert('creation canceled');
        };
    })
;
