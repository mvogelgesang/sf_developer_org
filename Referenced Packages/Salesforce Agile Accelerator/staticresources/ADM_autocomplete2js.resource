
/**
 * @namespace
 */
var autocomplete2 = {};

autocomplete2.Promise = function() {
    
    this._callbacks = {
        done: new autocomplete2.Promise.CallbackList(),
        fail: new autocomplete2.Promise.CallbackList()
    };
    
    this._state = 'pending';
};
autocomplete2.Promise.prototype = {
    resolve: function() {
        this._state = 'resolved';
        this._cache = arguments;
        this._callbacks.done.invoke(this, this._cache);
    },
    reject: function() {
        this._state = 'rejected';
        this._cache = arguments;
        this._callbacks.fail.invoke(this, this._cache);
    },
    done: function(callback) {
        if(this._state === 'pending') {
            this._callbacks.done.push(callback);
        } else if(this._state === 'resolved') {
            callback.apply(this, this._cache);
        }
        return this;
    },
    fail: function(callback) {
        if(this._state === 'pending') {
            this._callbacks.fail.push(callback);
        } else if(this._state === 'rejected') {
            callback.apply(this, this._cache);
        }
        return this;
    }
}

autocomplete2.Promise.CallbackList = function() {
    this.items = [];
    
    this.invoke = function(context, arguments) {
        for(var index = 0; index < this.items.length; index++) {
            this.items[index].apply(context, arguments);
        }
    };
    
    this.push = function(item) {
        this.items.push(item);
    };
};

autocomplete2.AutoComplete = function(options) {
    this.source = options.source;
    this.setElement(options.$input);
    this.selected = options.selected;
};
/*
Bug fix https://gus.my.salesforce.com/apex/adm_bugdetail?id=a07B0000000bGJjIAM&sfdc.override=1
W-1889864
Removed Change event from autocomplete which was setting selected to null and causing the 
input text to blank out on blur
*/
autocomplete2.AutoComplete.prototype = {
    setElement: function(el) {
        if(this.$input) {
            this.$input.removeData('gus-autocomplete');
        }
        
        //expects a jQuery context
        this.$input = el;
        this.$input.data('gus-autocomplete', this);
        
        this.on('change:selected', $.proxy(this.updateInput, this));
    },
    render: function() {
        var view = this;
        this.$input.autocomplete({
            source: this.source,
            select: function(event, ui) {
                return view._onSelect(event, ui);
            },
            focus: function(event, ui) {
                view.$input.val(ui.item.Name);
                $(view).trigger('focus', ui);
                return false;
            }
        });
        
        if(this.renderItem) {
            if (this.$input.data('autocomplete')) {
                this.$input.data("autocomplete")._renderItem = this.renderItem;
            } else {
                $.ui.autocomplete.prototype._renderItem = this.renderItem;
            }
        }
        
        return this;
    },
    renderItem: function(ul, item) {
        //make sure the item has a value property
        if(typeof item.value === 'undefined') {
            item.value = item.Name;
        }
        
        return $("<li>")
            .data("item.autocomplete", item)
            .append($("<a>").text(item.Name))
            .appendTo(ul);
    },
    errorHandler: function(messages) {
        //since autocomplete is not crucial, we will fallback 
        //gracefully by dumping the message to the console, but 
        //not alerting the user.
        console.warn('Errors occurred while trying to retrieve autocomplete values');
        console.log(messages);
    },
    updateInput: function() {
        //console.log('updateInput');
        if(this.selected) {
            this.$input.val(this.selected.Name);
            if (this.selected.SmallPhotoUrl) {
                $(this.$input).closest('.input-prepend').find('.input-prepend-col1 img').attr('src',this.selected.SmallPhotoUrl);
            }
            if (this.selected.Id) {
                if ($(this.$input).attr('id').indexOf(":") == -1) {
                    $(this.$input).parent().find('#' + $(this.$input).attr('id') + 'Hidden').remove();
                    $(this.$input).parent().append($('<input type="hidden" class="hiddenIdHolder" id="' + $(this.$input).attr('id') + 'Hidden" name="' + $(this.$input).attr('id') + 'Hidden" value="' + this.selected.Id + '" />'));
                }
            }
        }
    },
    getSelected: function() {
        return this.selected;
    },
    setSelected: function(value) {
        this.selected = value;
        this.trigger('change:selected');
        this.trigger('select');
    },
    
    trigger: function() {
        return $.prototype.trigger.apply($(this), arguments);
    },
    on: function() {
        return $.prototype.bind.apply($(this), arguments);
    },
    
    /**
     * invoked by jQuery UI autocomplete select event
     */
    _onSelect: function(event, ui) {
        var selected = null;
        
        //normalize the jQuery UI value
        if(ui.item) {
            selected = $.extend({}, ui.item);
            delete selected.value;
            delete selected.label;
        }
        
        this.setSelected(selected);
        return true;
    }
};

autocomplete2.searchSObjectArray = function(results, request, response) {
    var term = request.term;
    
    //filter the list of sObjects by the Name property
    var matcher = new RegExp(term.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&"), "i");
    var filtered = $.grep(results, function(value) {
        return matcher.test(value.Name || value);
    });
    
    response(filtered);
};

/**
 * Creates a source callback that searches over an array of sObjects for item that match the Name property
 */
autocomplete2.createSObjectArraySource = function(results) {
    return function(request, response) {
        autocomplete2.searchSObjectArray(results, request, response);
    };
};

autocomplete2.createCachedRemoteActionSource = function(/**String*/ name, /**Function**/ loaderFunction) {
    var root = autocomplete2;
    if(typeof root._queries === 'undefined') {
        root._queries = {};
    }
    
    //check the cache to see if the query is already started to load
    var query = root._queries[name];
    if(typeof query === 'undefined' || query == null) {
        console.debug('retrieving query ' + name);
    
        //start the execution of a new query
        query = new autocomplete2.Promise();
        loaderFunction(function(result, event){
            if(event.status) {
                query.resolve.apply(query, arguments);
            } else {
                query.reject.apply(query, arguments);
            }
        }, {escape:false});
    
        root._queries[name] = query;
    }
    
    return function(request, response) {
        var f = this;
        if(typeof f._results !== 'undefined') {
            autocomplete2.searchSObjectArray(f._results, request, response);
        } else {
            query
                .done(function(results) {
                    f._results = results;
                    autocomplete2.searchSObjectArray(results, request, response);
                })
                .fail(function(result, event) {
                    console.warn('Errors occurred while trying to retrieve autocomplete values');
                    console.log(event);
                });
        }
    };
};

/**
 * Creates a source callback that executes the query against the server through AJAX
 */
autocomplete2.createGenericQuerySource = function(queryName, scrumteamId) {
    var errorHandler = function(event) {
        console.warn('Errors occurred while trying to retrieve autocomplete values');
        console.log(event);
    };

    return function(request, response) {
        //escape any wildcard characters in the search term
        var searchTerm = request.term.replace('%', '\\%');
     
        //wrap the term in wildcards
        searchTerm = '%' + searchTerm + '%';
     
        var params = {
            scrumteamId : scrumteamId
        };
        //console.log('createGenericQuerySource() queryName:' + queryName);
        agf.ADM_AutoComplete2Controller.searchSuggestions(searchTerm, queryName, params, function(result, event) {
            var responseValue = null;
         
            if(event.status) {
                if(result.errorMessages.length > 0) {
                    errorHandler(result.errorMessages);
                } else {
                    responseValue = result.results;
                }
            } else {
                errorHandler([event.message]);
            }
         
            //response must be called for autocomplete to stay in
            //the proper state
            response((responseValue == null)? [] : responseValue);
        }, {escape:false});
    };
};

autocomplete2.initialize = function(options){
    var source = null,
        queryName = options.queryName,
        scrumteamId = options.scrumteamId;
    
    //console.log('initialize() queryName:' + options.queryName);    

    //create the source for the specified queryName
    if(queryName.toLowerCase() === 'user') {
        source = autocomplete2.createCachedRemoteActionSource('user', agf.ADM_AutoComplete2Controller.getAllUsers);
    } else if(queryName.toLowerCase() === 'scrum') {
        source = autocomplete2.createCachedRemoteActionSource('team', agf.ADM_AutoComplete2Controller.getAllTeams);
    } else {

        source = autocomplete2.createGenericQuerySource(queryName, scrumteamId);
    }
    options.source = source;
    
    return new autocomplete2.AutoComplete(options);
}

/**
 * Gets the input element that is associated to the autocomplete component at 
 * the specified ID.
 */
autocomplete2.getInputElement = function(/**String*/ componentId) {
    var element = document.getElementById(componentId + ':autoCompleteComp:autoComp');
    if(element == null) {
        console.warn('No autocomplete component found with ID of \'' + componentId + '\'. Returning null.');
    }
    return element;
}
