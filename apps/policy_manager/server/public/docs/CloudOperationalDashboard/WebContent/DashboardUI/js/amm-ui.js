

$(function() {
    $(window).bind("load resize", function() {
        //topOffset = 50;
        width = (this.window.innerWidth > 0) ? this.window.innerWidth : this.screen.width;
        if (width < 768) {
            //$('span.status-state').addClass('collapse');
            //$('span.service-brand').addClass('collapse');
        } else {
           // $('span.status-state').removeClass('collapse');
            //$('span.service-brand').removeClass('collapse');
        }
/*
        height = (this.window.innerHeight > 0) ? this.window.innerHeight : this.screen.height;
        height = height - topOffset;
        if (height < 1) height = 1;
        if (height > topOffset) {
            $("#page-wrapper").css("min-height", (height) + "px");
        } */
    })
})