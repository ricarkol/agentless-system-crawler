
pathArray = window.location.href.split('/');
var appContext = pathArray[3];
var hostvalue = pathArray[2];
var protocolType=pathArray[0];
var protocol=protocolType+"//"+hostvalue;
var firstLoad= true;
var tableRef = null;

var selectedNameSpace = "";
var selectedTime = "";
var myplot;
var desidence; //Timezone of selected timestamp

$(document).ready(function(){

	buildNameSelection();
	buildTable();
	
	// In the case that the StatusTime.html or StatusName.html call this page
	if ($.cookie("namespace") != null) {
		selectedNameSpace = $.cookie("namespace");
		$.removeCookie("namespace");
		selectedTime = $.cookie("timestamp");
		$.removeCookie("timestamp");

		desidence = selectedTime.substring(19);
	
		getVulnerability();
		buildchart();
	}
	
});


function buildNameSelection() {

	var url = protocol + "/api/get_namespace_list";

	$.ajax({
		type : 'GET',
		scriptCharset: 'utf-8',
		url : url,
		dataType : "json", // data type of response
		contentType : "application/json",
		success : function(json){

			var availableTags = json;

			$( "#autoNameinput" ).autocomplete({

  				source: availableTags,
  				minLength: 0,
  				select: function(event, ui) {
  					$('#autoTimeinput').val("");
  					selectedTime = "";
  					selectedNameSpace = ui.item.label;
					buildTimeSelection();
					getVulnerability();
					buildchart();
  				}
  			});
			
		},
		error:function(){console.log('Miss..');}
	}); 

	$( '#autoNameinput' ).click( function () {
		$( '#autoNameinput' ).autocomplete( 'search', '' );
	});
}


function buildTimeSelection() {

	var url = protocol + "/api/get_crawl_times?namespace=" + encodeURIComponent(selectedNameSpace);

	$.ajax({
		type : 'GET',
		scriptCharset: 'utf-8',
		url : url,
		dataType : "json", // data type of response
		contentType : "application/json",
		success : function(json){

			var availableTags = json;
			desidence = json[0].substring(19);

			$( "#autoTimeinput" ).autocomplete({

  				source: availableTags,
  				minLength: 0,
  				select: function(event, ui) {
  					selectedTime = ui.item.label;
					getVulnerability();
  				}
  			});
			
		},
		error:function(){console.log('Miss..');}
	}); 

	$( '#autoTimeinput' ).click( function () {
		$( '#autoTimeinput' ).autocomplete( 'search', '' );
	});
}


function buildTable(){

	tableRef = $("#dtable").dataTable({
		
		"aoColumns": [       		              		
		    {"mData": "usnid"},     
		    {"mData": "vcheck" },      
		    {"mData": "description"}
		],

		"columnDefs": [
    		{ "width": "20%", "targets": 0 },
    		{ "width": "10%", "targets": 1 },
 		],

		"scrollY": 450,
        "scrollX": true,
		"paging": false,
		"aData": null,
		"order": [[ 1, "desc" ]],
		"scrollCollapse": false,

		"oLanguage": {
		   "sEmptyTable": "No records found",
		   "sLoadingRecords": "Loading...",
		   "sProcessing": "DataTables is currently busy"
		},			

		"dom": '<"row" <"col-lg-4"<"upper-left">><"col-lg-6 text-center"lf><"col-lg-2"<"upper-right text-right">>>t<"row"<"col-lg-3"<"text-left"i>><"col-lg-6 text-center"p><"col-lg-3"<"lower-right text-right">>>'
			
	});

}


function getVulnerability() {

	var url = protocol + "/api/get_vulnerability_page?namespace=" + encodeURIComponent(selectedNameSpace);

	if (selectedTime != "") {
		url = url + "&timestamp=" + encodeURIComponent(selectedTime);
	}

	tableRef.fnClearTable();

	var oFeatures = tableRef.fnSettings();
	oFeatures.bProcessing  = true;
	oFeatures.bServerSide = true;
	
	oFeatures.oLanguage.sEmptyTable = oFeatures.oLanguage.sLoadingRecords;
	tableRef.fnDraw();

	//console.log(url);
	
	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json", // data type of response
		contentType : "application/json",
		success : callShowResult,

	});

}


function buildchart() {
	if (myplot != null) {
		myplot.destroy();
	}

	var ajaxDataRenderer = function(url, plot, options) {
		var ret = null;
		$.ajax({
			async: false,
			url: url,
			dataType:"json",
			success: function(data) {
				ret = data;
			},
			error: function(XMLHttpRequest, textStatus, errorThrown){
				console.log("error...");
			}
		});
		return ret;
	};

	var url = protocol + "/api/get_vulnerability_counts?namespace=" + encodeURIComponent(selectedNameSpace);

 	myplot = $.jqplot('canvas', url, {
	    grid: {
            background: '#efeff1'
        }, 
        height: 150,

	    stackSeries: true,
	    seriesDefaults:{
		   	renderer: $.jqplot.BarRenderer,
	     	rendererOptions: {
		   		barWidth: 10
	    	}
		},
      	pointLabels: {show: true},
		series: [
            {color: '#ff8888'}, {color: '#ccccff'}
        ],

	    axes:{
	        xaxis:{
	            renderer: $.jqplot.DateAxisRenderer
	            //tickOptions:{
	            //    formatString: '%B'
	            //},
	        }
	    },
	    dataRenderer: ajaxDataRenderer,
	    dataRendererOptions: {
	      	unusedOptionalUrl: url
	    }
    });

 	$('#canvas').unbind('jqplotDataClick');
   	$('#canvas').bind('jqplotDataClick', 
    	function (ev, seriesIndex, pointIndex, data) {

            var date = myplot.data[seriesIndex][pointIndex][0];
            date = date.replace(" ","T");
            selectedTime = date + desidence;
  	        getVulnerability();
    	}
  	); 

 	$('#canvas').bind('jqplotDataHighlight', 
        function (ev, seriesIndex, pointIndex, data ) {
            var mouseX = ev.pageX-250; //these are going to be how jquery knows where to put the div that will be our tooltip
            var mouseY = ev.pageY-200;


            var t = myplot.data[seriesIndex][pointIndex][0];
            var v = myplot.data[seriesIndex][pointIndex][1];

            $('#info3').html(t + ', ' + v);
            var cssObj = {
                'position' : 'absolute',
                'font-weight' : 'bold',
                'left' : mouseX + 'px', //usually needs more offset here
                'top' : mouseY + 'px'
            };
            $('#info3').css(cssObj);
        }
    );    

    $('#canvas').bind('jqplotDataUnhighlight', 
        function (ev) {
            $('#info3').html('');
        }
    );
}



function callShowResult(data) {

	//$("div.upper-left").html("<p>Namespace: " + data.namespace + "<br> Timestamp: " + data.crawl_time + "</p>");
	$("div.upper-right").html('<p><font size="6" color="#ff3333">' + data.overall + '</font></p>');

	var message = "No data available.";

	var flag = 0;
	var dataFound = false;
	var iTotalRecords = 0;
	var iTotalDisplayRecords = 0;
	var data1 = '{"sEcho": 1, "iTotalRecords": 2, "iTotalDisplayRecords":2,"aaData":[';

	$.each(data.vulnerability, function(object, Object) {

		if (data == "") {
			console.log(messge);
			message = "No data available.";
			$('#errorDiv').addClass("alert alert-info");
			$('#errorDiv').html(
					"<strong>Information. </strong>No rule available.");
			flag = 1;

		} else if (data != null) {

			if (Object.Message != null) {
				message = Object.Message;
				console.log(message);
				$('#errorDiv').addClass("alert alert-danger");
				$('#errorDiv').html("<strong>Error. </strong>" + message);

				flag = 1;
			} else {
				dataFound = true;

				data1 = data1 + '{"usnid":"' + Object.usnid + '",';
				data1 = data1 + '"vcheck":"' + Object.check + '",';
				data1 = data1 + '"description":"' + Object.description+ '"},';
			}
		}

	});

	if (dataFound) {
		data1 = data1.slice(0, data1.lastIndexOf(","))
				+ data1.substring(data1.lastIndexOf(",") + 1);
	}

	if (flag == 0 && !dataFound) {
		message = "No rule available.";
		$('#errorDiv').addClass("alert alert-info");
		$('#errorDiv').html("<strong>Information </strong>No data available.");
	}

	data1 = data1 + "]}";

	//console.log("compliance status:" + data1);

	var da = JSON.parse(data1);
	da.iTotalRecords = iTotalRecords;
	da.iTotalDisplayRecords = iTotalDisplayRecords;

	if (da.aaData.length) {
		tableRef.fnAddData(da.aaData);
		var oFeatures = tableRef.fnSettings();
		oFeatures.oLanguage.sEmptyTable = "No records found";
	} else {
		tableRef.fnClearTable();
		var oFeatures = tableRef.fnSettings();
		oFeatures.oLanguage.sEmptyTable = "No records found";
	}

	tableRef.fnDraw();

	changeFailColor();

}


function changeFailColor() {

	$('#dtable > tbody > tr').each(function () {
        $(this).children("td").each(function () {
        	if ($(this).text() == "Vulnerable") {
        		$(this).attr('class', 'fail');
        	}
	    });
    });
	
}

