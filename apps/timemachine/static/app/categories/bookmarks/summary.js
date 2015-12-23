/**
 * Created by sastryduri on 4/23/15.
 */

angular.module('categories.bookmarks.summary', [
    'tm.models.bookmarks',
    'checklist-model'
])
    .config(function($stateProvider){

    })
    .controller('BookmarksSummaryCtrl', function(BookmarksModel, $stateParams){
        var bookmarksSummaryCtrl = this;
        bookmarksSummaryCtrl.summary = {
            "total": 50000,
            "last_week": 423,
            "last_day": 37
        };

        bookmarksSummaryCtrl.bookmark_query = {};
        bookmarksSummaryCtrl.bookmarks = [];
        bookmarksSummaryCtrl.displayedBookmarks = [];
        bookmarksSummaryCtrl.selectedBookmarkList = [];
        bookmarksSummaryCtrl.diff_results = {};
        bookmarksSummaryCtrl.display_diff_results = false;
        bookmarksSummaryCtrl.display_bookmarks = true;

        bookmarksSummaryCtrl.cancelDisplay = cancelDisplay;
        bookmarksSummaryCtrl.findBookmarks = findBookmarks;
        bookmarksSummaryCtrl.addBookmark = addBookmark;
        bookmarksSummaryCtrl.deleteBookmark = deleteBookmark;
        bookmarksSummaryCtrl.listChanged = listChanged;
        bookmarksSummaryCtrl.diffBookmarks = diffBookmarks;
        bookmarksSummaryCtrl.disableDiff = true;


        function clearForm(){
            bookmarksSummaryCtrl.newBookmark = {};
        }

        function findBookmarks(queryBookmark){
            BookmarksModel.invalidateCachedBookmarks();
            BookmarksModel.getBookmarks(queryBookmark).then(function(bookmarks){
                bookmarksSummaryCtrl.bookmarks = bookmarks;
                bookmarksSummaryCtrl.displayedBookmarks = [].concat(bookmarks);
                bookmarksSummaryCtrl.display_bookmarks = true;
                bookmarksSummaryCtrl.display_diff_results = false;

            });
        };

        function addBookmark(bookmark){
            BookmarksModel.addBookmark(bookmark);
            bookmarksSummaryCtrl.newBookmark = {};
        };

        function listChanged(bookmark){

            if (bookmarksSummaryCtrl.selectedBookmarkList.length === 2){
                bookmarksSummaryCtrl.disableDiff = false;
            }else {
                bookmarksSummaryCtrl.disableDiff = true;
            }

        };

        function deleteBookmark(bookmark){
            BookmarksModel.deleteBookmark(bookmark);
        };

        function diffBookmarks(){
            bookmarksSummaryCtrl.diff_results = [];
            BookmarksModel.diffBookmarks(bookmarksSummaryCtrl.selectedBookmarkList[0],
                bookmarksSummaryCtrl.selectedBookmarkList[1]).then(function(diff_results){
                bookmarksSummaryCtrl.diff_results = diff_results;
                    bookmarksSummaryCtrl.display_diff_results = true;
                    bookmarksSummaryCtrl.display_bookmarks = false;
            });
        }
        function cancelDisplay(){
            clearForm();
            bookmarksSummaryCtrl.display_bookmarks = false;
            bookmarksSummaryCtrl.display_diff_results = false;
        };


    })
;
