
if (!document.Portals) {
    document.Portals = {};
}
if (!document.Portals.WebApi) {
    document.Portals.WebApi = {};
}

/* define window.webapi*/
(function (webapi, $) {
    function safeAjax(ajaxOptions) {
        var deferredAjax = $.Deferred();

        shell.getTokenDeferred().done(function (token) {
            // add headers for AJAX
            if (!ajaxOptions.headers) {
                $.extend(ajaxOptions, {
                    headers: {
                        "__RequestVerificationToken": token
                    }
                });
            } else {
                ajaxOptions.headers["__RequestVerificationToken"] = token;
            }
            $.ajax(ajaxOptions)
                .done(function (data, textStatus, jqXHR) {
                    validateLoginSession(data, textStatus, jqXHR, deferredAjax.resolve);
                }).fail(deferredAjax.reject); //AJAX
        }).fail(function () {
            deferredAjax.rejectWith(this, arguments); // on token failure pass the token AJAX and args
        });

        return deferredAjax.promise();
    }
    // define the standard safeAjax
    webapi.safeAjax = safeAjax;

    // additionally define the ajaxSafePost, so it is compatible with
    // with the implementation below that relise on the shell for on-prem
    webapi.ajaxSafePost = safeAjax;
})(window.webapi = window.webapi || {}, jQuery)


document.Portals.WebApi = {
    /**
     * Make a Convergence JSON request
     * @param {string} jsonKey
     * @param {Object} jsonArgs
     * @param {Function} successCallback
     * @param {Function} errorCallback
     * 
     * Example:
     *   document.XrmPortal.JSON.GetJsonData("getSnippetData", {
     *        snippetList: "snippet1,snippet2,snippet3"
     *        }, function success (){}, function failure (){});
     */
    GetJsonData: function (jsonKey, jsonArgs, successCallback, errorCallback) {
        var jsonQueryParameters = "";
        Object.keys(jsonArgs).forEach(function (key, resultIndex) {
            jsonQueryParameters += key + "=" + jsonArgs[key] + "&";
        });
        var requestUrl = `/${lang}/json/?request=${jsonKey}&${jsonQueryParameters}`;
        return $.ajax({
            url: requestUrl,
            contentType: 'application/json'
        }).fail(function (jqXHR, textStatus, error) {
            if (errorCallback) {
                errorCallback(jqXHR, textStatus, error);
            }
            else {
                console.log("Request failed: " + textStatus);
                console.log(jqXHR);
                console.log(error);
            }
        }).done(function (result) {
            if (successCallback) {
                successCallback(result);
            }
        });
    },

    /**
     * Documentation for endpoint: https://docs.microsoft.com/en-us/powerapps/maker/portals/read-operations
     * @param {string} entitySetName The entity logical set name (plural version of the entity logical name)
     * @param {Guid} id The Guid of the entity to retrieve
     * @param {Array} attributes Array of the columns/attributes to be retreived.
     * Returns ajax promise - chaing using .then
     */
    RetrieveEntity: function (entitySetName, id, attributes) {
        var select = "";
        // if the attributes are the expected array
        // join the select string.
        if (Array.isArray(attributes)) {
            select = attributes.join(",");
        }

        var requestUrl = "/_api/" + entitySetName + "(" + id + ")?$select=" + select;
        return webapi.ajaxSafePost({
            url: requestUrl,
            contentType: 'application/json'
        });;
    },

    /**
     * Documentation for endpoint: https://docs.microsoft.com/en-us/powerapps/maker/portals/write-update-delete-operations#update-and-delete-records-by-using-the-web-api
     * @param {string} entitySetName
     * @param {Guid} id
     * @param {any} entityData
     * 
     * Returns ajax promise - chaing using .then
     */
    UpdateEntity: function (entitySetName, id, entityData) {

        var requestUrl = "/_api/" + entitySetName + "(" + id + ")";
        return webapi.ajaxSafePost({
            url: requestUrl,
            contentType: 'application/json',
            method: 'PATCH', // Update is a Patch request
            data: JSON.stringify(entityData)
        });
    },

    /**
     * @param {string} entitySetName
     * @param {Guid} id
     * 
     * Poke a cloud instance entity to refrech 
     * To use the target entity must have a column with the name 
     * "rp_cacherefresh" of the datetime type. This will then
     * update the entity column the current datetime triggering the 
     * entity record cache to be cleared and refreshed.
     * 
     * Ensure table permissions and site settings are configured approperately 
     * Returns ajax promise - chaing using .then
     */
    UpdateEntityColumn: function (entitySetName, id, columnName, value) {
        // put url, directly to the attribute being updated
        var requestUrl = "/_api/" + entitySetName + "(" + id + ")/" + columnName;
        return webapi.ajaxSafePost({
            url: requestUrl,
            contentType: 'application/json',
            method: 'PUT', // Update a column is PUT
            // setting the value of the cache refresh field
            data: JSON.stringify({
                "value": value
            })
        });
    },


    /**
     * Documentation for endpoint: https://docs.microsoft.com/en-us/powerapps/maker/portals/write-update-delete-operations#create-a-record-in-a-table
     * @param {string} entitySetName
     * @param {any} entityData
     * Returns ajax promise - chaing using .then 
     */
    CreateEntity: function (entitySetName, entityData) {
        var entityId = null;
        var requestUrl = "/_api/" + entitySetName;
        return webapi.ajaxSafePost({
            url: requestUrl,
            contentType: 'application/json',
            method: 'POST', // Update is a Patch request
            data: JSON.stringify(entityData),
            success: function (res, status, xhr) {
                entityId = xhr.getResponseHeader("entityid");
                //print id of newly created table record
                console.log("entityID: " + xhr.getResponseHeader("entityid"))
            }
        }).then(value => {
            console.log(value);
            return entityId;
        });
    },


    /**
     * Documentation for endpoint: https://docs.microsoft.com/en-us/powerapps/maker/portals/write-update-delete-operations#update-and-delete-records-by-using-the-web-api
     * @param {string} entitySetName The entity logical set name (plural version of the entity logical name)
     * @param {Guid} id The Guid of the entity to retrieve
     * Returns ajax promise - chaing using .then
     */
    DeleteEntity: function (entitySetName, id) {

        var requestUrl = "/_api/" + entitySetName + "(" + id + ")";
        return webapi.ajaxSafePost({
            type: "DELETE",
            url: requestUrl,
            contentType: 'application/json'
        });;
    },

    /**
     * Documentation for endpoint: https://docs.microsoft.com/en-us/powerapps/maker/portals/write-update-delete-operations#update-and-delete-records-by-using-the-web-api
     * @param {string} entitySetName The entity logical set name (plural version of the entity logical name)
     * @param {Guid} id The Guid of the entity to retrieve
     * Returns ajax promise - chaing using .then
     */
    DeleteEntityAttribute: function (entitySetName, id, attribute) {

        var requestUrl = "/_api/" + entitySetName + "(" + id + ")/" + attribute;
        return webapi.ajaxSafePost({
            type: "DELETE",
            url: requestUrl,
            contentType: 'application/json'
        });
    },

    /**
     * Documentation for endpoint: https://docs.microsoft.com/en-us/powerapps/maker/portals/write-update-delete-operations#associate-and-disassociate-tables-by-using-the-web-api
     * @param {any} sourceEntitySetName
     * @param {any} sourceId
     * @param {any} relationshipName
     * @param {any} targetEntitySetName
     * @param {any} sourceId
     */
    AssociateEntity: function (sourceEntitySetName, sourceId, relationshipName, targetEntitySetName, targetId) {
        var requestUrl = "/_api/" + sourceEntitySetName + "(" + sourceId + ")/" + relationshipName + "/$ref";
        return webapi.ajaxSafePost(
            {
                type: "POST",
                url: requestUrl,
                contentType: "application/json",
                data: JSON.stringify({
                    "@odata.id": window.location.origin + "/_api/" + targetEntitySetName + "(" + targetId + ")"
                })
            });
    },

    /**
     * Documentation for endpoint: https://docs.microsoft.com/en-us/powerapps/maker/portals/write-update-delete-operations#associate-and-disassociate-tables-by-using-the-web-api
     * @param {any} sourceEntitySetName
     * @param {any} sourceId
     * @param {any} relationshipName
     * @param {any} targetEntitySetName
     * @param {any} targetId
     * */
    DisassociateEntity: function (sourceEntitySetName, sourceId, relationshipName, targetEntitySetName, targetId) {
        var requestUrl = "/_api/" + sourceEntitySetName + "(" + sourceId + ")/" + relationshipName + "/$ref?$id=" + window.location.origin + "/_api/" + targetEntitySetName + "(" + targetId + ")";
        return webapi.ajaxSafePost(
            {
                type: "DELETE",
                url: requestUrl,
                contentType: "application/json",
            });
    },


    /**
     * @param {string} entitySetName
     * @param {Guid} id
     * 
     * Poke a cloud instance entity to refrech 
     * To use the target entity must have a column with the name 
     * "rp_cacherefresh" of the datetime type. This will then
     * update the entity column the current datetime triggering the 
     * entity record cache to be cleared and refreshed.
     * 
     * Ensure table permissions and site settings are configured approperately 
     * Returns ajax promise - chaing using .then
     */
    RefreshEntityCache: function (entitySetName, id, columnName) {

        var date = new Date();
        if (columnName === undefined || columnName == "") {
            columnName = "mnp_refreshcache"
        }

        // put url, directly to the attribute being updated
        var requestUrl = "/_api/" + entitySetName + "(" + id + ")/" + columnName;
        return webapi.ajaxSafePost({
            url: requestUrl,
            contentType: 'application/json',
            method: 'PUT', // Update a column is PUT
            // setting the value of the cache refresh field
            data: JSON.stringify({
                "value": date.toISOString()
            })
        });
    },

    /**
     * @param {string} entitySetName
     * @param {Guid} id
     * 
     */
    UploadFile: function (entitySetName, entityId, fileColumn, filename, fileContent) {
        return webapi.safeAjax({
            type: "PUT", // NOTE: right now Portals requires PUT instead of PATCH for the upload
            url: `/_api/${entitySetName}(${entityId})/${fileColumn}?x-ms-file-name=${fileName}`,
            contentType: "application/octet-stream",
            data: fileContent,
            processData: false,
            success: function (data, textStatus, xhr) {
                console.log("File uploaded");
            },
            error: function (xhr, textStatus, errorThrown) {
                console.log(xhr);
            }
        });
    },

    DownloadFile: function (entitySetName, entityId, fileColumn, defaultFileName) {
        if (defaultFileName === undefined || defaultFileName === null) {
            defaultFileName = "file.bin"
        }
        return webapi.safeAjax({
            type: "GET",
            url: `/_api/${entitySetName}(${entityId})/${fileColumn}/$value`,
            contentType: "application/json",
            xhr: function () { var xhr = new XMLHttpRequest(); xhr.responseType = "blob"; return xhr; },
            success: function (data, textStatus, xhr) {
                var fileContent = data; // Binary
                var fileName = defaultFileName; // default name

                // NOTE: the following code decodes the file name from the header
                var contentDisposition = xhr.getResponseHeader("Content-Disposition");
                try {
                    var strToCheck = "filename=";
                    var mimeEncodingCheck = "\"=?utf-8?B?";
                    if (contentDisposition.indexOf(strToCheck) > 0) {
                        var parseFileName = contentDisposition.substring(contentDisposition.indexOf(strToCheck) + strToCheck.length);
                        if (parseFileName.indexOf(mimeEncodingCheck) === -1) { fileName = parseFileName; }
                        else {
                            var parseFileNameBase64 = parseFileName.substring(parseFileName.indexOf(mimeEncodingCheck) + mimeEncodingCheck.length, parseFileName.length - 3);
                            fileName = decodeURIComponent(atob(parseFileNameBase64).split("").map(function (c) { return "%" + ("00" + c.charCodeAt(0).toString(16)).slice(-2); }).join(""));
                        }
                    }
                } catch { }

                console.log("File retrieved. Name: " + fileName);

                // NOTE: If you need to convert fileContent to Base 64, check FileReader API "readAsDataURL" passing the Binary content as Blob

                // NOTE: Uncomment the following lines to download the file
                var saveFile = new Blob([fileContent], { type: "application/octet-stream" });
                var customLink = document.createElement("a");
                customLink.href = URL.createObjectURL(saveFile);
                customLink.download = fileName;
                customLink.click();
            }
        });
    }

}