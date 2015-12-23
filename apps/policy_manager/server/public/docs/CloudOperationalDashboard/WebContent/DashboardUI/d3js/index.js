 
    $(document).ready(function() {     	
    	
        //getContainersandRules();
    	getImages();
       
     });
    
    
    
    
    function getImages(){  
    	
    	$.ajax({
    		type: "GET",
    		contentType: "application/json; charset=utf-8",
    		url: 'https://kasa.sl.cloud9.ibm.com:9292/api/images'  ,
    		dataType: 'json',
    		async: true,
    		data: "{}", 
    		success: function (data) {  
    			var images = [[]];
    			var json = data;	    			
    			$.each(json, function(idx, obj) {    		
    				var sub = [];
    				sub.push(obj.image_id);
    				sub.push(obj.image_name);
    				sub.push(obj.id);
    				sub.push(obj.created);
    				images.push(sub);  				
    				
    			});  
    			
    			
    			$('#demo').html( '<table cellpadding="0" cellspacing="0" border="0" class="display" id="example"></table>' );
    			 
    		    $('#example').dataTable( {
    		        "data": images,
    		        "columns": [
    		            { "title": "Image Id" , "class": "center" },
    		            { "title": "Image Name" ,"class": "center"},
    		            { "title": "Container Id" , "class": "center"},
    		            { "title": "Created", "class": "center" },
    		           
    		        ]
    		    } );   
    			
    			
    			
    			
    			//getContainerTimestamps(images);
    			//getRules(containers);
    			//dsBarChart(div_name,get_data);			   
    		},
    		error: function (xhr, status, error) {		
    			$("#divErrorMessages").empty().append(status);
                $("#divErrorMessages").append(xhr.responseText);
                
                alert(xhr.responseText);
    		}
    	});     	
    }
    
    
    function getImageCheckingTimestamps(){  
    	
    	//var imageText = '{"image_id":"", "":""'
    	
    	$.ajax({
    		type: "GET",
    		contentType: "application/json; charset=utf-8",
    		url: 'https://kasa.sl.cloud9.ibm.com:9292/api/containers'  ,
    		dataType: 'json',
    		async: true,
    		data: "{}", 
    		success: function (data) {  
    			var images = {};
	    			
    			//
    			$.each(data, function(object, Object) {    		
    				var sub = [];
    				sub.push(obj.image_id);
    				sub.push(obj.image_name);
    				sub.push(obj.id);
    				sub.push(obj.created);
    				images.push(sub);  				
    				
    			});   			
    			
    			//getRules(containers);
    			//dsBarChart(div_name,get_data);			   
    		},
    		error: function (xhr, status, error) {		
    			$("#divErrorMessages").empty().append(status);
                $("#divErrorMessages").append(xhr.responseText);
                
                alert(xhr.responseText);
    		}
    	});     	
    }
    
    
 