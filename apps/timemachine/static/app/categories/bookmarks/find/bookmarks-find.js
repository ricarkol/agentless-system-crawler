angular.module('categories.bookmarks.find', [
    'smart-table',
    'tm.models.bookmarks'
])
    .config(function($stateProvider){

        $stateProvider.state('tm.categories.bookmarks.find', {
            url:"/find",
            views: {
                'categories@':{
                    controller: 'BookmarksOptionsCtrl as bookmarksOptionsCtrl',
                    templateUrl: 'static/app/categories/bookmarks/options.tmpl.html'
                },
                'summary@':{
                    controller: 'FindBookmarkCtrl as findBookmarkCtrl',
                    templateUrl: 'static/app/categories/bookmarks/find/bookmarks-find.tmpl.html'
                }
                //'timeline@':{
                //    controller: 'BookmarksTimelineCtrl as bookmarksTimelineCtrl',
                //    templateUrl: 'static/app/categories/bookmarks/timeline.tmpl.html'
                //}
            }
        })
    }).controller('FindBookmarkCtrl', function FindBookmarkCtrl(BookmarksModel, $scope){
        var findBookmarkCtrl = this;

        findBookmarkCtrl.newBookmark = {};
        findBookmarkCtrl.findBookmark = findBookmark;
        findBookmarkCtrl.cancelFinding = cancelFinding;
        findBookmarkCtrl.removeItem = removeItem;
        $scope.bookmarks = [];
        $scope.displayedBookmarks = [];


        function findBookmark (bookmark){
            BookmarksModel.getBookmarks()
                .then(function(bookmarks){
                    $scope.bookmarks = bookmarks;
                    $scope.displayedBookmarks = [].concat(bookmarks);
                });
        };

        function cancelFinding (){
            findBookmarkCtrl.newBookmark = {};
            //$scope.bookmarks = [];
            //$scope.displayedBookmarks = [];
        };

        function removeItem(row) {
            var index = $scope.bookmarks.indexOf(row);
            if (index !== -1) {
                $scope.bookmarks.splice(index, 1);
            }
        }
    })
;
