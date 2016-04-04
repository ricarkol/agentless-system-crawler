
pathArray = window.location.href.split('/');
var appContext = pathArray[3];
var hostvalue = pathArray[2];
var protocolType=pathArray[0];
var protocol=protocolType+"//"+hostvalue;
var firstLoad= true;
var tableRef = null;


$(document).ready(function(){
	
	buildAutoComplete();
	
	buildTable();
	
	// In the case that the StatusTime.html call this page
	if ($.cookie("namespace") != null) {
		getStatus($.cookie("namespace"));
		$.removeCookie("namespace");
	}

});


function buildAutoComplete() {

	var url = protocol + "/api/get_namespace_list";

	$.ajax({
		type : 'GET',
		scriptCharset: 'utf-8',
		url : url,
		dataType : "json", // data type of response
		contentType : "application/json",
		success : function(json){

			var availableTags = json;

			$( "#autocomplete" ).autocomplete({

  				source: availableTags,
  				minLength: 0,
  				select: function(event, ui) {
  					getStatus(ui.item.label);
  				}
  			});
			
		},
		error:function(){console.log('Miss..');}
	}); 

	$( '#autocomplete' ).click( function () {
		$( '#autocomplete' ).autocomplete( 'search', '' );
	});
}


function buildTable(){

	tableRef = $("#dtable").dataTable({
		
		"aoColumns": [       		              		 
		    {"mData": "tenant" },      
		    {"mData": "namespace"},      
		    {"mData": "crawl_time"},
		    {"mData": "vulnerability"},
		    {"mData": "compliance"},
		    {"mData": "1-1-a", sDefaultContent: "Pass"},
		    {"mData": "2-1-b", sDefaultContent: "Pass"},
		    {"mData": "2-1-c", sDefaultContent: "Pass"},
		    {"mData": "2-1-d", sDefaultContent: "Pass"},
		    {"mData": "5-1-a", sDefaultContent: "Pass"},
		    {"mData": "5-1-b", sDefaultContent: "Pass"},
		    {"mData": "5-1-d", sDefaultContent: "Pass"},
		    {"mData": "5-1-d", sDefaultContent: "Pass"},
		    {"mData": "5-1-e", sDefaultContent: "Pass"},
		    {"mData": "5-1-f", sDefaultContent: "Pass"},
		    {"mData": "5-1-j", sDefaultContent: "Pass"},
		    {"mData": "5-1-k", sDefaultContent: "Pass"},
		    {"mData": "5-1-l", sDefaultContent: "Pass"},
		    {"mData": "5-1-m", sDefaultContent: "Pass"},
		    {"mData": "5-1-s", sDefaultContent: "Pass"},
		    {"mData": "6-1-d", sDefaultContent: "Pass"},
		    {"mData": "6-1-e", sDefaultContent: "Pass"},
		    {"mData": "6-1-f", sDefaultContent: "Pass"},
		    {"mData": "8-0-o", sDefaultContent: "Pass"}
		],


		"scrollY": 450,
        "scrollX": true,
		"paging": false,
		"aData": null,
		"order": [[ 3, "desc" ]],
		"scrollCollapse": false,

		"oLanguage": {
		   "sEmptyTable": "No records found",
		   "sLoadingRecords": "Loading...",
		   "sProcessing": "DataTables is currently busy"
		},			

		"dom": '<"row" <"col-lg-4"<"upper-left">><"col-lg-6 text-center"lf><"col-lg-2"<"upper-right text-right">>>t<"row"<"col-lg-3"<"text-left"i>><"col-lg-6 text-center"p><"col-lg-3"<"lower-right text-right">>>'
		//"dom": '<"row"<"col-lg-4"<"upper-left">><"col-lg-6 text-center"><"col-lg-2"<"upper-right text-right"lf>>>t<"row"<"col-lg-3"<"text-left"i>><"col-lg-6 text-center"p><"col-lg-3"<"lower-right text-right">>>'
			
	});

}


function callShowResult(data) {

	//setLabels();

	var message = "No data available.";

	var flag = 0;
	var dataFound = false;
	var iTotalRecords = 0;
	var iTotalDisplayRecords = 0;
	var data1 = '{"sEcho": 1, "iTotalRecords": 2, "iTotalDisplayRecords":2,"aaData":[';

	$.each(data, function(object, Object) {

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
				// flag = 0
				//console.log("**** " + Object.tenant);
				//console.log("**** " + Object.results["1_1_a"]);
				
				data1 = data1 + '{"tenant":' + '"' + Object.tenant + '"' + ",";
				data1 = data1 + '"namespace":' + '"' + Object.namespace + '"' + ",";
				data1 = data1 + '"crawl_time":' + '"' + Object.crawl_time + '"' + ",";
				data1 = data1 + '"vulnerability":' + '"' + Object.vulnerability + '"' + ",";
				data1 = data1 + '"compliance":' + '"' + Object.compliance + '"';

				if (Object.compliance == "PASS") {
					data1 = data1 + "},";
				} else {
					data1 = data1 + ",";
				
					data1 = data1 + '"1-1-a":' + '"' + Object.results["Linux.1-1-a"] + '"' + ",";
					data1 = data1 + '"2-1-b":' + '"' + Object.results["Linux.2-1-b"] + '"' + ",";
					data1 = data1 + '"2-1-c":' + '"' + Object.results["Linux.2-1-c"] + '"' + ",";
					data1 = data1 + '"2-1-d":' + '"' + Object.results["Linux.2-1-d"] + '"' + ",";
					data1 = data1 + '"5-1-a":' + '"' + Object.results["Linux.5-1-d"] + '"' + ",";
				  	data1 = data1 + '"5-1-b":' + '"' + Object.results["Linux.5-1-f"] + '"' + ",";
				  	data1 = data1 + '"5-1-d":' + '"' + Object.results["Linux.5-1-d"] + '"' + ",";
				    data1 = data1 + '"5-1-e":' + '"' + Object.results["Linux.5-1-e"] + '"' + ",";
				    data1 = data1 + '"5-1-f":' + '"' + Object.results["Linux.5-1-f"] + '"' + ",";	    
					data1 = data1 + '"5-1-j":' + '"' + Object.results["Linux.5-1-j"] + '"' + ",";
				    data1 = data1 + '"5-1-k":' + '"' + Object.results["Linux.5-1-k"] + '"' + ",";
				    data1 = data1 + '"5-1-l":' + '"' + Object.results["Linux.5-1-l"] + '"' + ",";
				    data1 = data1 + '"5-1-m":' + '"' + Object.results["Linux.5-1-m"] + '"' + ",";
				    data1 = data1 + '"5-1-s":' + '"' + Object.results["Linux.5-1-s"] + '"' + ",";
				    data1 = data1 + '"6-1-d":' + '"' + Object.results["Linux.6-1-d"] + '"' + ",";
				    data1 = data1 + '"6-1-e":' + '"' + Object.results["Linux.6-1-e"] + '"' + ",";
				    data1 = data1 + '"6-1-f":' + '"' + Object.results["Linux.6-1-f"] + '"' + ",";
				    data1 = data1 + '"8-0-o":' + '"' + Object.results["Linux.8-0-o"] + '"' + "},";
				}
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
	setClickEvent();

}


function setClickEvent() {

	$('#dtable > tbody > tr').on('click', 'td:eq(3)',  function () {
        $.cookie("namespace", $(this).prev().prev().text());
        $.cookie("timestamp", $(this).prev().text());
        window.location.href = 'VStatusTime.html';
    } );
}


function changeFailColor() {

	$('#dtable > tbody > tr').each(function () {
        $(this).children("td").each(function () {
        	if ($(this).text() == "FAIL" || $(this).text() == "Fail") {
        		$(this).attr('class', 'fail');
        	}
	    });
    });
	
}



function getStatus(namespace) {

	$("div.upper-left").html("<p> Status of " + namespace + "</p>");

	tableRef.fnClearTable();

	var oFeatures = tableRef.fnSettings();
	oFeatures.bProcessing  = true;
	oFeatures.bServerSide = true;
	
	oFeatures.oLanguage.sEmptyTable = oFeatures.oLanguage.sLoadingRecords;
	tableRef.fnDraw();

	var url = protocol + "/api/get_result_page_per_namespace?namespace=" + encodeURIComponent(namespace);
	
	$.ajax({
		type : 'GET',
		url : url,
		dataType : "json", // data type of response
		contentType : "application/json",
		success : callShowResult,

	});   
}
