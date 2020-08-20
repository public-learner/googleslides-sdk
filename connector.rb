{
  title: "Google Slides",
  connection: {
    fields: [
      {
        name: "client_id",
        hint: "https://console.developers.google.com/apis/credentials
              Redirect URI is https://www.workato.com/oauth/callback",
              optional: false
      },
      {
        name: "client_secret",
        hint: "https://console.developers.google.com/apis/credentials",
        optional: false,
        control_type: "password"
      }
    ],
    authorization: {
      type: "oauth2",
      authorization_url: lambda do |connection|
        scopes = [
          "https://www.googleapis.com/auth/drive",
          "https://www.googleapis.com/auth/presentations"
        ].join(" ")
        params = {
          client_id: connection["client_id"],
          response_type: "code",
          scope: scopes,
          access_type: "offline",
          include_granted_scopes: "true",
          prompt: "consent" 
        }.to_param

        "https://accounts.google.com/o/oauth2/auth?" + params
      end,
      acquire: lambda do |connection, auth_code|
        response = post("https://accounts.google.com/o/oauth2/token").
          payload(
            client_id: connection["client_id"],
            client_secret: connection["client_secret"],
            grant_type: "authorization_code",
            code: auth_code,
            redirect_uri: "https://www.workato.com/oauth/callback").
            request_format_www_form_urlencoded
        [response, nil, nil]
      end,
      refresh: lambda do |connection, refresh_token|
        post("https://accounts.google.com/o/oauth2/token").
          payload(
            client_id: connection["client_id"],
            client_secret: connection["client_secret"],
            grant_type: "refresh_token",
            refresh_token: refresh_token).
            request_format_www_form_urlencoded
      end,
      apply: lambda do |_connection, access_token|
        headers("Authorization": "Bearer #{access_token}")
      end
    },
    base_uri: lambda do |_connection|
      "https://slides.googleapis.com"
    end
  },
  test: lambda do |_connection|
    get("/$discovery/rest?version=v1")
  end,
  actions: {
    get_presentation: {
      title: "Get Presentation",
      input_fields: lambda do |_object_definitions|
        [
          {
            name: "presentation_id",
            optional: false
          }
        ]
      end,
      execute: lambda do |connection, input|
        get("/v1/presentations/#{input["presentation_id"]}")
      end,
      output_fields: lambda do |object_definitions|
        object_definitions["presentation"]
      end
    },
    update_presentation: {
      title: "Update Presentation",
      hint: "Select one request type (e.g. replace text, or replace images) per action. See Google Slides API documentation for more information.",
      input_fields: lambda do |object_definitions|
        [
          {
            name: "presentation_id",
            optional: false
          },
          {
            name: "replace_all_text",
            type: :array,
            of: :object,
            optional: true,
            properties: object_definitions["replace_all_text"]
          },
          {
            name: "insert_table_rows",
            type: :array,
            of: :object,
            optional: true,
            properties: object_definitions["insert_table_rows"]
          },
          {
            name: "insert_text",
            type: :array,
            of: :object,
            optional: true,
            properties: object_definitions["insert_text"]
          },
          {
            name: "create_image",
            type: :array,
            of: :object,
            optional: true,
            properties: object_definitions["create_image"]
          },
          {
            name: "replace_image",
            type: :array,
            of: :object,
            optional: true,
            properties: object_definitions["replace_image"]
          }
        ]
      end,
      execute: lambda do |connection, input|
        input["writeControl"] = {
          "requiredRevisionId": get("/v1/presentations/#{input["presentation_id"]}")["revisionId"]
        }

        slide_contents = get("/v1/presentations/#{input["presentation_id"]}")
        images = {}
        slide_contents["slides"].each do |slide|
          slide["pageElements"].each do |element|
            if element["title"].present?
              images[element["title"]] = element["objectId"]
            end
          end
        end
        
        request_types = [
          "replace_all_text",
          "insert_table_rows",
          "insert_text",
          "create_image",
          "replace_image"
        ]
        requests = []
        request_types.each do |request_type|
          if input[request_type].present? && request_type == "replace_image"
            input[request_type].each do |replaceImageRequest|
              requests << {
                "replaceImage": {
                  "imageObjectId": images[replaceImageRequest["replaceImage"]["imageTitle"]],
                  "imageReplaceMethod": "CENTER_CROP",
                  "url": replaceImageRequest["replaceImage"]["url"]
                }
              }
            end
          elsif input[request_type].present?
            requests = requests + input[request_type]
          end
        end
        post("/v1/presentations/#{input["presentation_id"]}:batchUpdate").
          payload({
          "presentation_id": input["presentation_id"],
          "requests": requests
        })
      end,
      output_fields: lambda do |object_definitions|
        object_definitions["update_response"]
      end
    }
  },
  object_definitions: {
    replace_all_text: {
      fields: lambda do
        [
          {
            "properties": [
              {
                "control_type": "text",
                "optional": false,
                "label": "Replace with",
                "type": "string",
                "name": "replaceText"
              },
              {
                "properties": [
                  {
                    "control_type": "text",
                    "optional": false,
                    "label": "Find text",
                    "type": "string",
                    "name": "text"
                  },
                  {
                    "control_type": "checkbox",
                    "optional": false,
                    "label": "Case sensitive match",
                    "toggle_hint": "Select from option list",
                    "toggle_field": {
                      "label": "Case sensitive match",
                      "control_type": "text",
                      "toggle_hint": "Use custom value",
                      "hint": "Accepts true or false only",
                      "type": "boolean",
                      "name": "matchCase"
                    },
                    "type": "boolean",
                    "name": "matchCase"
                  }
                ],
                "label": "Find",
                "optional": false,
                "type": "object",
                "name": "containsText"
              }
            ],
            "label": "Replace all text",
            "type": "object",
            "name": "replaceAllText"
          }
        ]
      end
    },
    insert_table_rows: {
      fields: lambda do
        [
          {
            "label": "Insert table rows",
            "optional": false,
            "type": "object",
            "name": "insertTableRows",
            "properties": [
              {
                "control_type": "text",
                "label": "Table object ID",
                "type": "string",
                "name": "tableObjectId"
              },
              {
                "properties": [
                  {
                    "control_type": "number",
                    "label": "Row index",
                    "parse_output": "float_conversion",
                    "type": "number",
                    "name": "rowIndex"
                  },
                  {
                    "control_type": "number",
                    "label": "Column index",
                    "parse_output": "float_conversion",
                    "type": "number",
                    "name": "columnIndex"
                  }
                ],
                "label": "Cell location",
                "type": "object",
                "name": "cellLocation"
              },
              {
                "control_type": "text",
                "label": "Insert below",
                "render_input": {},
                "parse_output": {},
                "toggle_hint": "Select from option list",
                "toggle_field": {
                  "label": "Insert below",
                  "control_type": "text",
                  "toggle_hint": "Use custom value",
                  "type": "boolean",
                  "name": "insertBelow"
                },
                "type": "boolean",
                "name": "insertBelow"
              },
              {
                "control_type": "number",
                "label": "Number",
                "parse_output": "float_conversion",
                "type": "number",
                "name": "number"
              }
            ]
          }
        ]
      end
    },
    insert_text: {
      fields: lambda do
        [
          {
            "label": "Insert text",
            "optional": false,
            "type": "object",
            "name": "insertText",
            "properties": [
              {
                "control_type": "text",
                "label": "Object ID",
                "type": "string",
                "name": "objectId"
              },
              {
                "properties": [
                  {
                    "control_type": "number",
                    "label": "Row index",
                    "parse_output": "float_conversion",
                    "type": "number",
                    "name": "rowIndex"
                  },
                  {
                    "control_type": "number",
                    "label": "Column index",
                    "parse_output": "float_conversion",
                    "type": "number",
                    "name": "columnIndex"
                  }
                ],
                "label": "Cell location",
                "type": "object",
                "name": "cellLocation"
              },
              {
                "name": "text"
              },
              {
                "control_type": "number",
                "label": "Insertion index",
                "parse_output": "float_conversion",
                "type": "number",
                "name": "insertionIndex"
              }
            ]
          }
        ]
      end
    },
    create_image: {
      fields: lambda do
        [
          {
            "label": "Create image",
            "optional": false,
            "type": "object",
            "name": "createImage",
            "properties": [
              {
                "control_type": "text",
                "hint": "User-supplied ID",
                "label": "Object ID",
                "type": "string",
                "name": "objectId"
              },
              {
                "properties": [
                  {
                    "name": "pageObjectId"
                  },
                  {
                    "name": "size",
                    "type": "object",
                    "properties": [
                      {
                        "name": "width",
                        "type": "object",
                        "properties": [
                          {
                            "name": "magnitude",
                            "type": "number"
                          },
                          {
                            "name": "unit"
                          }
                        ]
                      },
                      {
                        "name": "height",
                        "type": "object",
                        "properties": [
                          {
                            "name": "magnitude",
                            "type": "number"
                          },
                          {
                            "name": "unit"
                          }
                        ]
                      }
                    ]
                  },
                  {
                    "name": "transform",
                    "type": "object",
                    "properties": [
                      {
                        "name": "scaleX",
                        "type": "number"
                      },
                      {
                        "name": "scaleY",
                        "type": "number"
                      },
                      {
                        "name": "shearX",
                        "type": "number"
                      },
                      {
                        "name": "shearY",
                        "type": "number"
                      },
                      {
                        "name": "translateX",
                        "type": "number"
                      },
                      {
                        "name": "translateY",
                        "type": "number"
                      },
                      {
                        "name": "unit"
                      }
                    ]
                  }
                ],
                "label": "Element properties",
                "type": "object",
                "name": "elementProperties"
              },
              {
                "name": "url"
              }
            ]
          }
        ]
      end
    },
    replace_image: {
      fields: lambda do
				[
				  {
				    "properties": [
				      {
				        "control_type": "text",
				        "label": "Image title",
				        "type": "string",
                "hint": "Add a title in Slides by right-clicking and selecting 'Alt text'",
                "name": "imageTitle"
				      },
				      {
				        "control_type": "text",
				        "label": "URL",
				        "type": "string",
				        "name": "url"
				      }
				    ],
				    "label": "Replace image",
				    "type": "object",
				    "name": "replaceImage"
				  }
				]
      end
    },
    presentation: {
      fields: lambda do
        [
          {
            "control_type": "text",
            "label": "Presentation ID",
            "type": "string",
            "name": "presentationId"
          },
          {
            "properties": [
              {
                "properties": [
                  {
                    "control_type": "number",
                    "label": "Magnitude",
                    "parse_output": "float_conversion",
                    "type": "number",
                    "name": "magnitude"
                  },
                  {
                    "control_type": "text",
                    "label": "Unit",
                    "type": "string",
                    "name": "unit"
                  }
                ],
                "label": "Width",
                "type": "object",
                "name": "width"
              },
              {
                "properties": [
                  {
                    "control_type": "number",
                    "label": "Magnitude",
                    "parse_output": "float_conversion",
                    "type": "number",
                    "name": "magnitude"
                  },
                  {
                    "control_type": "text",
                    "label": "Unit",
                    "type": "string",
                    "name": "unit"
                  }
                ],
                "label": "Height",
                "type": "object",
                "name": "height"
              }
            ],
            "label": "Page size",
            "type": "object",
            "name": "pageSize"
          },
          {
            "name": "slides",
            "type": "array",
            "of": "object",
            "label": "Slides",
            "properties": [
              {
                "control_type": "text",
                "label": "Object ID",
                "type": "string",
                "name": "objectId"
              },
              {
                "name": "pageElements",
                "type": "array",
                "of": "object",
                "label": "Page elements",
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Object ID",
                    "type": "string",
                    "name": "objectId"
                  },
                  {
                    "properties": [
                      {
                        "properties": [
                          {
                            "control_type": "number",
                            "label": "Magnitude",
                            "parse_output": "float_conversion",
                            "type": "number",
                            "name": "magnitude"
                          },
                          {
                            "control_type": "text",
                            "label": "Unit",
                            "type": "string",
                            "name": "unit"
                          }
                        ],
                        "label": "Width",
                        "type": "object",
                        "name": "width"
                      },
                      {
                        "properties": [
                          {
                            "control_type": "number",
                            "label": "Magnitude",
                            "parse_output": "float_conversion",
                            "type": "number",
                            "name": "magnitude"
                          },
                          {
                            "control_type": "text",
                            "label": "Unit",
                            "type": "string",
                            "name": "unit"
                          }
                        ],
                        "label": "Height",
                        "type": "object",
                        "name": "height"
                      }
                    ],
                    "label": "Size",
                    "type": "object",
                    "name": "size"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "number",
                        "label": "Scale X",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "scaleX"
                      },
                      {
                        "control_type": "number",
                        "label": "Scale Y",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "scaleY"
                      },
                      {
                        "control_type": "number",
                        "label": "Translate X",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "translateX"
                      },
                      {
                        "control_type": "number",
                        "label": "Translate Y",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "translateY"
                      },
                      {
                        "control_type": "text",
                        "label": "Unit",
                        "type": "string",
                        "name": "unit"
                      }
                    ],
                    "label": "Transform",
                    "type": "object",
                    "name": "transform"
                  },
                  {
                    "properties": [
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "control_type": "text",
                                        "label": "Theme color",
                                        "type": "string",
                                        "name": "themeColor"
                                      }
                                    ],
                                    "label": "Color",
                                    "type": "object",
                                    "name": "color"
                                  },
                                  {
                                    "control_type": "number",
                                    "label": "Alpha",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "alpha"
                                  }
                                ],
                                "label": "Solid fill",
                                "type": "object",
                                "name": "solidFill"
                              }
                            ],
                            "label": "Line fill",
                            "type": "object",
                            "name": "lineFill"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "Magnitude",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "magnitude"
                              },
                              {
                                "control_type": "text",
                                "label": "Unit",
                                "type": "string",
                                "name": "unit"
                              }
                            ],
                            "label": "Weight",
                            "type": "object",
                            "name": "weight"
                          },
                          {
                            "control_type": "text",
                            "label": "Dash style",
                            "type": "string",
                            "name": "dashStyle"
                          },
                          {
                            "control_type": "text",
                            "label": "Start arrow",
                            "type": "string",
                            "name": "startArrow"
                          },
                          {
                            "control_type": "text",
                            "label": "End arrow",
                            "type": "string",
                            "name": "endArrow"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Connected object ID",
                                "type": "string",
                                "name": "connectedObjectId"
                              },
                              {
                                "control_type": "number",
                                "label": "Connection site index",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "connectionSiteIndex"
                              }
                            ],
                            "label": "End connection",
                            "type": "object",
                            "name": "endConnection"
                          }
                        ],
                        "label": "Line properties",
                        "type": "object",
                        "name": "lineProperties"
                      },
                      {
                        "control_type": "text",
                        "label": "Line type",
                        "type": "string",
                        "name": "lineType"
                      },
                      {
                        "control_type": "text",
                        "label": "Line category",
                        "type": "string",
                        "name": "lineCategory"
                      }
                    ],
                    "label": "Line",
                    "type": "object",
                    "name": "line"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "text",
                        "label": "Content URL",
                        "type": "string",
                        "name": "contentUrl"
                      },
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "properties": [
                                          {
                                            "control_type": "text",
                                            "label": "Theme color",
                                            "type": "string",
                                            "name": "themeColor"
                                          }
                                        ],
                                        "label": "Color",
                                        "type": "object",
                                        "name": "color"
                                      },
                                      {
                                        "control_type": "number",
                                        "label": "Alpha",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "alpha"
                                      }
                                    ],
                                    "label": "Solid fill",
                                    "type": "object",
                                    "name": "solidFill"
                                  }
                                ],
                                "label": "Outline fill",
                                "type": "object",
                                "name": "outlineFill"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Magnitude",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "magnitude"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Weight",
                                "type": "object",
                                "name": "weight"
                              },
                              {
                                "control_type": "text",
                                "label": "Dash style",
                                "type": "string",
                                "name": "dashStyle"
                              },
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Outline",
                            "type": "object",
                            "name": "outline"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Type",
                                "type": "string",
                                "name": "type"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Scale X",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "scaleX"
                                  },
                                  {
                                    "control_type": "number",
                                    "label": "Scale Y",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "scaleY"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Transform",
                                "type": "object",
                                "name": "transform"
                              },
                              {
                                "control_type": "text",
                                "label": "Alignment",
                                "type": "string",
                                "name": "alignment"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Blur radius",
                                "type": "object",
                                "name": "blurRadius"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [],
                                    "label": "Rgb color",
                                    "type": "object",
                                    "name": "rgbColor"
                                  }
                                ],
                                "label": "Color",
                                "type": "object",
                                "name": "color"
                              },
                              {
                                "control_type": "number",
                                "label": "Alpha",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "alpha"
                              },
                              {
                                "control_type": "text",
                                "label": "Rotate with shape",
                                "render_input": {},
                                "parse_output": {},
                                "toggle_hint": "Select from option list",
                                "toggle_field": {
                                  "label": "Rotate with shape",
                                  "control_type": "text",
                                  "toggle_hint": "Use custom value",
                                  "type": "boolean",
                                  "name": "rotateWithShape"
                                },
                                "type": "boolean",
                                "name": "rotateWithShape"
                              },
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Shadow",
                            "type": "object",
                            "name": "shadow"
                          }
                        ],
                        "label": "Image properties",
                        "type": "object",
                        "name": "imageProperties"
                      }
                    ],
                    "label": "Image",
                    "type": "object",
                    "name": "image"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "number",
                        "label": "Rows",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "rows"
                      },
                      {
                        "control_type": "number",
                        "label": "Columns",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "columns"
                      },
                      {
                        "name": "tableRows",
                        "type": "array",
                        "of": "object",
                        "label": "Table rows",
                        "properties": [
                          {
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "Magnitude",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "magnitude"
                              },
                              {
                                "control_type": "text",
                                "label": "Unit",
                                "type": "string",
                                "name": "unit"
                              }
                            ],
                            "label": "Row height",
                            "type": "object",
                            "name": "rowHeight"
                          },
                          {
                            "name": "tableCells",
                            "type": "array",
                            "of": "object",
                            "label": "Table cells",
                            "properties": [
                              {
                                "properties": [],
                                "label": "Location",
                                "type": "object",
                                "name": "location"
                              },
                              {
                                "control_type": "number",
                                "label": "Row span",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "rowSpan"
                              },
                              {
                                "control_type": "number",
                                "label": "Column span",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "columnSpan"
                              },
                              {
                                "properties": [
                                  {
                                    "name": "textElements",
                                    "type": "array",
                                    "of": "object",
                                    "label": "Text elements",
                                    "properties": [
                                      {
                                        "control_type": "number",
                                        "label": "End index",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "endIndex"
                                      },
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "control_type": "number",
                                                "label": "Line spacing",
                                                "parse_output": "float_conversion",
                                                "type": "number",
                                                "name": "lineSpacing"
                                              },
                                              {
                                                "control_type": "text",
                                                "label": "Alignment",
                                                "type": "string",
                                                "name": "alignment"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Indent start",
                                                "type": "object",
                                                "name": "indentStart"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Indent end",
                                                "type": "object",
                                                "name": "indentEnd"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Space above",
                                                "type": "object",
                                                "name": "spaceAbove"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Space below",
                                                "type": "object",
                                                "name": "spaceBelow"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Indent first line",
                                                "type": "object",
                                                "name": "indentFirstLine"
                                              },
                                              {
                                                "control_type": "text",
                                                "label": "Direction",
                                                "type": "string",
                                                "name": "direction"
                                              },
                                              {
                                                "control_type": "text",
                                                "label": "Spacing mode",
                                                "type": "string",
                                                "name": "spacingMode"
                                              }
                                            ],
                                            "label": "Style",
                                            "type": "object",
                                            "name": "style"
                                          }
                                        ],
                                        "label": "Paragraph marker",
                                        "type": "object",
                                        "name": "paragraphMarker"
                                      }
                                    ]
                                  }
                                ],
                                "label": "Text",
                                "type": "object",
                                "name": "text"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "control_type": "text",
                                        "label": "Property state",
                                        "type": "string",
                                        "name": "propertyState"
                                      },
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "number",
                                                    "label": "Red",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "red"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Green",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "green"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Blue",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "blue"
                                                  }
                                                ],
                                                "label": "Rgb color",
                                                "type": "object",
                                                "name": "rgbColor"
                                              }
                                            ],
                                            "label": "Color",
                                            "type": "object",
                                            "name": "color"
                                          },
                                          {
                                            "control_type": "number",
                                            "label": "Alpha",
                                            "parse_output": "float_conversion",
                                            "type": "number",
                                            "name": "alpha"
                                          }
                                        ],
                                        "label": "Solid fill",
                                        "type": "object",
                                        "name": "solidFill"
                                      }
                                    ],
                                    "label": "Table cell background fill",
                                    "type": "object",
                                    "name": "tableCellBackgroundFill"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Content alignment",
                                    "type": "string",
                                    "name": "contentAlignment"
                                  }
                                ],
                                "label": "Table cell properties",
                                "type": "object",
                                "name": "tableCellProperties"
                              }
                            ]
                          },
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Magnitude",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "magnitude"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Min row height",
                                "type": "object",
                                "name": "minRowHeight"
                              }
                            ],
                            "label": "Table row properties",
                            "type": "object",
                            "name": "tableRowProperties"
                          }
                        ]
                      },
                      {
                        "name": "tableColumns",
                        "type": "array",
                        "of": "object",
                        "label": "Table columns",
                        "properties": [
                          {
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "Magnitude",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "magnitude"
                              },
                              {
                                "control_type": "text",
                                "label": "Unit",
                                "type": "string",
                                "name": "unit"
                              }
                            ],
                            "label": "Column width",
                            "type": "object",
                            "name": "columnWidth"
                          }
                        ]
                      },
                      {
                        "name": "horizontalBorderRows",
                        "type": "array",
                        "of": "object",
                        "label": "Horizontal border rows",
                        "properties": [
                          {
                            "name": "tableBorderCells",
                            "type": "array",
                            "of": "object",
                            "label": "Table border cells",
                            "properties": [
                              {
                                "properties": [],
                                "label": "Location",
                                "type": "object",
                                "name": "location"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "number",
                                                    "label": "Red",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "red"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Green",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "green"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Blue",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "blue"
                                                  }
                                                ],
                                                "label": "Rgb color",
                                                "type": "object",
                                                "name": "rgbColor"
                                              }
                                            ],
                                            "label": "Color",
                                            "type": "object",
                                            "name": "color"
                                          },
                                          {
                                            "control_type": "number",
                                            "label": "Alpha",
                                            "parse_output": "float_conversion",
                                            "type": "number",
                                            "name": "alpha"
                                          }
                                        ],
                                        "label": "Solid fill",
                                        "type": "object",
                                        "name": "solidFill"
                                      }
                                    ],
                                    "label": "Table border fill",
                                    "type": "object",
                                    "name": "tableBorderFill"
                                  },
                                  {
                                    "properties": [
                                      {
                                        "control_type": "number",
                                        "label": "Magnitude",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "magnitude"
                                      },
                                      {
                                        "control_type": "text",
                                        "label": "Unit",
                                        "type": "string",
                                        "name": "unit"
                                      }
                                    ],
                                    "label": "Weight",
                                    "type": "object",
                                    "name": "weight"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Dash style",
                                    "type": "string",
                                    "name": "dashStyle"
                                  }
                                ],
                                "label": "Table border properties",
                                "type": "object",
                                "name": "tableBorderProperties"
                              }
                            ]
                          }
                        ]
                      },
                      {
                        "name": "verticalBorderRows",
                        "type": "array",
                        "of": "object",
                        "label": "Vertical border rows",
                        "properties": [
                          {
                            "name": "tableBorderCells",
                            "type": "array",
                            "of": "object",
                            "label": "Table border cells",
                            "properties": [
                              {
                                "properties": [],
                                "label": "Location",
                                "type": "object",
                                "name": "location"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "number",
                                                    "label": "Red",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "red"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Green",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "green"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Blue",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "blue"
                                                  }
                                                ],
                                                "label": "Rgb color",
                                                "type": "object",
                                                "name": "rgbColor"
                                              }
                                            ],
                                            "label": "Color",
                                            "type": "object",
                                            "name": "color"
                                          },
                                          {
                                            "control_type": "number",
                                            "label": "Alpha",
                                            "parse_output": "float_conversion",
                                            "type": "number",
                                            "name": "alpha"
                                          }
                                        ],
                                        "label": "Solid fill",
                                        "type": "object",
                                        "name": "solidFill"
                                      }
                                    ],
                                    "label": "Table border fill",
                                    "type": "object",
                                    "name": "tableBorderFill"
                                  },
                                  {
                                    "properties": [
                                      {
                                        "control_type": "number",
                                        "label": "Magnitude",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "magnitude"
                                      },
                                      {
                                        "control_type": "text",
                                        "label": "Unit",
                                        "type": "string",
                                        "name": "unit"
                                      }
                                    ],
                                    "label": "Weight",
                                    "type": "object",
                                    "name": "weight"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Dash style",
                                    "type": "string",
                                    "name": "dashStyle"
                                  }
                                ],
                                "label": "Table border properties",
                                "type": "object",
                                "name": "tableBorderProperties"
                              }
                            ]
                          }
                        ]
                      }
                    ],
                    "label": "Table",
                    "type": "object",
                    "name": "table"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "text",
                        "label": "Shape type",
                        "type": "string",
                        "name": "shapeType"
                      },
                      {
                        "properties": [
                          {
                            "name": "textElements",
                            "type": "array",
                            "of": "object",
                            "label": "Text elements",
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "End index",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "endIndex"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "text",
                                    "label": "Content",
                                    "type": "string",
                                    "name": "content"
                                  },
                                  {
                                    "properties": [],
                                    "label": "Style",
                                    "type": "object",
                                    "name": "style"
                                  }
                                ],
                                "label": "Text run",
                                "type": "object",
                                "name": "textRun"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "control_type": "text",
                                        "label": "Direction",
                                        "type": "string",
                                        "name": "direction"
                                      }
                                    ],
                                    "label": "Style",
                                    "type": "object",
                                    "name": "style"
                                  }
                                ],
                                "label": "Paragraph marker",
                                "type": "object",
                                "name": "paragraphMarker"
                              }
                            ]
                          }
                        ],
                        "label": "Text",
                        "type": "object",
                        "name": "text"
                      },
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Shape background fill",
                            "type": "object",
                            "name": "shapeBackgroundFill"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Outline",
                            "type": "object",
                            "name": "outline"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Shadow",
                            "type": "object",
                            "name": "shadow"
                          }
                        ],
                        "label": "Shape properties",
                        "type": "object",
                        "name": "shapeProperties"
                      },
                      {
                        "properties": [
                          {
                            "control_type": "text",
                            "label": "Type",
                            "type": "string",
                            "name": "type"
                          },
                          {
                            "control_type": "text",
                            "label": "Parent object ID",
                            "type": "string",
                            "name": "parentObjectId"
                          }
                        ],
                        "label": "Placeholder",
                        "type": "object",
                        "name": "placeholder"
                      }
                    ],
                    "label": "Shape",
                    "type": "object",
                    "name": "shape"
                  }
                ]
              },
              {
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Layout object ID",
                    "type": "string",
                    "name": "layoutObjectId"
                  },
                  {
                    "control_type": "text",
                    "label": "Master object ID",
                    "type": "string",
                    "name": "masterObjectId"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "text",
                        "label": "Object ID",
                        "type": "string",
                        "name": "objectId"
                      },
                      {
                        "control_type": "text",
                        "label": "Page type",
                        "type": "string",
                        "name": "pageType"
                      },
                      {
                        "name": "pageElements",
                        "type": "array",
                        "of": "object",
                        "label": "Page elements",
                        "properties": [
                          {
                            "control_type": "text",
                            "label": "Object ID",
                            "type": "string",
                            "name": "objectId"
                          },
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Magnitude",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "magnitude"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Width",
                                "type": "object",
                                "name": "width"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Magnitude",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "magnitude"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Height",
                                "type": "object",
                                "name": "height"
                              }
                            ],
                            "label": "Size",
                            "type": "object",
                            "name": "size"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "Scale X",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "scaleX"
                              },
                              {
                                "control_type": "number",
                                "label": "Scale Y",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "scaleY"
                              },
                              {
                                "control_type": "number",
                                "label": "Translate X",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "translateX"
                              },
                              {
                                "control_type": "number",
                                "label": "Translate Y",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "translateY"
                              },
                              {
                                "control_type": "text",
                                "label": "Unit",
                                "type": "string",
                                "name": "unit"
                              }
                            ],
                            "label": "Transform",
                            "type": "object",
                            "name": "transform"
                          },
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "control_type": "text",
                                        "label": "Property state",
                                        "type": "string",
                                        "name": "propertyState"
                                      }
                                    ],
                                    "label": "Outline",
                                    "type": "object",
                                    "name": "outline"
                                  }
                                ],
                                "label": "Shape properties",
                                "type": "object",
                                "name": "shapeProperties"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "text",
                                    "label": "Type",
                                    "type": "string",
                                    "name": "type"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Parent object ID",
                                    "type": "string",
                                    "name": "parentObjectId"
                                  }
                                ],
                                "label": "Placeholder",
                                "type": "object",
                                "name": "placeholder"
                              }
                            ],
                            "label": "Shape",
                            "type": "object",
                            "name": "shape"
                          }
                        ]
                      },
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Page background fill",
                            "type": "object",
                            "name": "pageBackgroundFill"
                          }
                        ],
                        "label": "Page properties",
                        "type": "object",
                        "name": "pageProperties"
                      },
                      {
                        "properties": [
                          {
                            "control_type": "text",
                            "label": "Speaker notes object ID",
                            "type": "string",
                            "name": "speakerNotesObjectId"
                          }
                        ],
                        "label": "Notes properties",
                        "type": "object",
                        "name": "notesProperties"
                      }
                    ],
                    "label": "Notes page",
                    "type": "object",
                    "name": "notesPage"
                  }
                ],
                "label": "Slide properties",
                "type": "object",
                "name": "slideProperties"
              },
              {
                "properties": [
                  {
                    "properties": [
                      {
                        "control_type": "text",
                        "label": "Property state",
                        "type": "string",
                        "name": "propertyState"
                      }
                    ],
                    "label": "Page background fill",
                    "type": "object",
                    "name": "pageBackgroundFill"
                  }
                ],
                "label": "Page properties",
                "type": "object",
                "name": "pageProperties"
              }
            ]
          },
          {
            "control_type": "text",
            "label": "Title",
            "type": "string",
            "name": "title"
          },
          {
            "name": "masters",
            "type": "array",
            "of": "object",
            "label": "Masters",
            "properties": [
              {
                "control_type": "text",
                "label": "Object ID",
                "type": "string",
                "name": "objectId"
              },
              {
                "control_type": "text",
                "label": "Page type",
                "type": "string",
                "name": "pageType"
              },
              {
                "properties": [
                  {
                    "properties": [
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Theme color",
                                "type": "string",
                                "name": "themeColor"
                              }
                            ],
                            "label": "Color",
                            "type": "object",
                            "name": "color"
                          },
                          {
                            "control_type": "number",
                            "label": "Alpha",
                            "parse_output": "float_conversion",
                            "type": "number",
                            "name": "alpha"
                          }
                        ],
                        "label": "Solid fill",
                        "type": "object",
                        "name": "solidFill"
                      }
                    ],
                    "label": "Page background fill",
                    "type": "object",
                    "name": "pageBackgroundFill"
                  },
                  {
                    "properties": [
                      {
                        "name": "colors",
                        "type": "array",
                        "of": "object",
                        "label": "Colors",
                        "properties": [
                          {
                            "control_type": "text",
                            "label": "Type",
                            "type": "string",
                            "name": "type"
                          },
                          {
                            "properties": [],
                            "label": "Color",
                            "type": "object",
                            "name": "color"
                          }
                        ]
                      }
                    ],
                    "label": "Color scheme",
                    "type": "object",
                    "name": "colorScheme"
                  }
                ],
                "label": "Page properties",
                "type": "object",
                "name": "pageProperties"
              },
              {
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Display name",
                    "type": "string",
                    "name": "displayName"
                  }
                ],
                "label": "Master properties",
                "type": "object",
                "name": "masterProperties"
              }
            ]
          },
          {
            "name": "layouts",
            "type": "array",
            "of": "object",
            "label": "Layouts",
            "properties": [
              {
                "control_type": "text",
                "label": "Object ID",
                "type": "string",
                "name": "objectId"
              },
              {
                "control_type": "text",
                "label": "Page type",
                "type": "string",
                "name": "pageType"
              },
              {
                "name": "pageElements",
                "type": "array",
                "of": "object",
                "label": "Page elements",
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Object ID",
                    "type": "string",
                    "name": "objectId"
                  },
                  {
                    "properties": [
                      {
                        "properties": [
                          {
                            "control_type": "number",
                            "label": "Magnitude",
                            "parse_output": "float_conversion",
                            "type": "number",
                            "name": "magnitude"
                          },
                          {
                            "control_type": "text",
                            "label": "Unit",
                            "type": "string",
                            "name": "unit"
                          }
                        ],
                        "label": "Width",
                        "type": "object",
                        "name": "width"
                      },
                      {
                        "properties": [
                          {
                            "control_type": "number",
                            "label": "Magnitude",
                            "parse_output": "float_conversion",
                            "type": "number",
                            "name": "magnitude"
                          },
                          {
                            "control_type": "text",
                            "label": "Unit",
                            "type": "string",
                            "name": "unit"
                          }
                        ],
                        "label": "Height",
                        "type": "object",
                        "name": "height"
                      }
                    ],
                    "label": "Size",
                    "type": "object",
                    "name": "size"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "number",
                        "label": "Scale X",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "scaleX"
                      },
                      {
                        "control_type": "number",
                        "label": "Scale Y",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "scaleY"
                      },
                      {
                        "control_type": "number",
                        "label": "Translate X",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "translateX"
                      },
                      {
                        "control_type": "number",
                        "label": "Translate Y",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "translateY"
                      },
                      {
                        "control_type": "text",
                        "label": "Unit",
                        "type": "string",
                        "name": "unit"
                      }
                    ],
                    "label": "Transform",
                    "type": "object",
                    "name": "transform"
                  },
                  {
                    "properties": [
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "control_type": "text",
                                        "label": "Theme color",
                                        "type": "string",
                                        "name": "themeColor"
                                      }
                                    ],
                                    "label": "Color",
                                    "type": "object",
                                    "name": "color"
                                  },
                                  {
                                    "control_type": "number",
                                    "label": "Alpha",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "alpha"
                                  }
                                ],
                                "label": "Solid fill",
                                "type": "object",
                                "name": "solidFill"
                              }
                            ],
                            "label": "Line fill",
                            "type": "object",
                            "name": "lineFill"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "Magnitude",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "magnitude"
                              },
                              {
                                "control_type": "text",
                                "label": "Unit",
                                "type": "string",
                                "name": "unit"
                              }
                            ],
                            "label": "Weight",
                            "type": "object",
                            "name": "weight"
                          },
                          {
                            "control_type": "text",
                            "label": "Dash style",
                            "type": "string",
                            "name": "dashStyle"
                          },
                          {
                            "control_type": "text",
                            "label": "Start arrow",
                            "type": "string",
                            "name": "startArrow"
                          },
                          {
                            "control_type": "text",
                            "label": "End arrow",
                            "type": "string",
                            "name": "endArrow"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Connected object ID",
                                "type": "string",
                                "name": "connectedObjectId"
                              },
                              {
                                "control_type": "number",
                                "label": "Connection site index",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "connectionSiteIndex"
                              }
                            ],
                            "label": "End connection",
                            "type": "object",
                            "name": "endConnection"
                          }
                        ],
                        "label": "Line properties",
                        "type": "object",
                        "name": "lineProperties"
                      },
                      {
                        "control_type": "text",
                        "label": "Line type",
                        "type": "string",
                        "name": "lineType"
                      },
                      {
                        "control_type": "text",
                        "label": "Line category",
                        "type": "string",
                        "name": "lineCategory"
                      }
                    ],
                    "label": "Line",
                    "type": "object",
                    "name": "line"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "text",
                        "label": "Content URL",
                        "type": "string",
                        "name": "contentUrl"
                      },
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "properties": [
                                          {
                                            "control_type": "text",
                                            "label": "Theme color",
                                            "type": "string",
                                            "name": "themeColor"
                                          }
                                        ],
                                        "label": "Color",
                                        "type": "object",
                                        "name": "color"
                                      },
                                      {
                                        "control_type": "number",
                                        "label": "Alpha",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "alpha"
                                      }
                                    ],
                                    "label": "Solid fill",
                                    "type": "object",
                                    "name": "solidFill"
                                  }
                                ],
                                "label": "Outline fill",
                                "type": "object",
                                "name": "outlineFill"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Magnitude",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "magnitude"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Weight",
                                "type": "object",
                                "name": "weight"
                              },
                              {
                                "control_type": "text",
                                "label": "Dash style",
                                "type": "string",
                                "name": "dashStyle"
                              },
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Outline",
                            "type": "object",
                            "name": "outline"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Type",
                                "type": "string",
                                "name": "type"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Scale X",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "scaleX"
                                  },
                                  {
                                    "control_type": "number",
                                    "label": "Scale Y",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "scaleY"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Transform",
                                "type": "object",
                                "name": "transform"
                              },
                              {
                                "control_type": "text",
                                "label": "Alignment",
                                "type": "string",
                                "name": "alignment"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Blur radius",
                                "type": "object",
                                "name": "blurRadius"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [],
                                    "label": "Rgb color",
                                    "type": "object",
                                    "name": "rgbColor"
                                  }
                                ],
                                "label": "Color",
                                "type": "object",
                                "name": "color"
                              },
                              {
                                "control_type": "number",
                                "label": "Alpha",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "alpha"
                              },
                              {
                                "control_type": "text",
                                "label": "Rotate with shape",
                                "render_input": {},
                                "parse_output": {},
                                "toggle_hint": "Select from option list",
                                "toggle_field": {
                                  "label": "Rotate with shape",
                                  "control_type": "text",
                                  "toggle_hint": "Use custom value",
                                  "type": "boolean",
                                  "name": "rotateWithShape"
                                },
                                "type": "boolean",
                                "name": "rotateWithShape"
                              },
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Shadow",
                            "type": "object",
                            "name": "shadow"
                          }
                        ],
                        "label": "Image properties",
                        "type": "object",
                        "name": "imageProperties"
                      }
                    ],
                    "label": "Image",
                    "type": "object",
                    "name": "image"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "number",
                        "label": "Rows",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "rows"
                      },
                      {
                        "control_type": "number",
                        "label": "Columns",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "columns"
                      },
                      {
                        "name": "tableRows",
                        "type": "array",
                        "of": "object",
                        "label": "Table rows",
                        "properties": [
                          {
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "Magnitude",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "magnitude"
                              },
                              {
                                "control_type": "text",
                                "label": "Unit",
                                "type": "string",
                                "name": "unit"
                              }
                            ],
                            "label": "Row height",
                            "type": "object",
                            "name": "rowHeight"
                          },
                          {
                            "name": "tableCells",
                            "type": "array",
                            "of": "object",
                            "label": "Table cells",
                            "properties": [
                              {
                                "properties": [],
                                "label": "Location",
                                "type": "object",
                                "name": "location"
                              },
                              {
                                "control_type": "number",
                                "label": "Row span",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "rowSpan"
                              },
                              {
                                "control_type": "number",
                                "label": "Column span",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "columnSpan"
                              },
                              {
                                "properties": [
                                  {
                                    "name": "textElements",
                                    "type": "array",
                                    "of": "object",
                                    "label": "Text elements",
                                    "properties": [
                                      {
                                        "control_type": "number",
                                        "label": "End index",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "endIndex"
                                      },
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "control_type": "number",
                                                "label": "Line spacing",
                                                "parse_output": "float_conversion",
                                                "type": "number",
                                                "name": "lineSpacing"
                                              },
                                              {
                                                "control_type": "text",
                                                "label": "Alignment",
                                                "type": "string",
                                                "name": "alignment"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Indent start",
                                                "type": "object",
                                                "name": "indentStart"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Indent end",
                                                "type": "object",
                                                "name": "indentEnd"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Space above",
                                                "type": "object",
                                                "name": "spaceAbove"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Space below",
                                                "type": "object",
                                                "name": "spaceBelow"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Indent first line",
                                                "type": "object",
                                                "name": "indentFirstLine"
                                              },
                                              {
                                                "control_type": "text",
                                                "label": "Direction",
                                                "type": "string",
                                                "name": "direction"
                                              },
                                              {
                                                "control_type": "text",
                                                "label": "Spacing mode",
                                                "type": "string",
                                                "name": "spacingMode"
                                              }
                                            ],
                                            "label": "Style",
                                            "type": "object",
                                            "name": "style"
                                          }
                                        ],
                                        "label": "Paragraph marker",
                                        "type": "object",
                                        "name": "paragraphMarker"
                                      }
                                    ]
                                  }
                                ],
                                "label": "Text",
                                "type": "object",
                                "name": "text"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "control_type": "text",
                                        "label": "Property state",
                                        "type": "string",
                                        "name": "propertyState"
                                      },
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "number",
                                                    "label": "Red",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "red"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Green",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "green"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Blue",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "blue"
                                                  }
                                                ],
                                                "label": "Rgb color",
                                                "type": "object",
                                                "name": "rgbColor"
                                              }
                                            ],
                                            "label": "Color",
                                            "type": "object",
                                            "name": "color"
                                          },
                                          {
                                            "control_type": "number",
                                            "label": "Alpha",
                                            "parse_output": "float_conversion",
                                            "type": "number",
                                            "name": "alpha"
                                          }
                                        ],
                                        "label": "Solid fill",
                                        "type": "object",
                                        "name": "solidFill"
                                      }
                                    ],
                                    "label": "Table cell background fill",
                                    "type": "object",
                                    "name": "tableCellBackgroundFill"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Content alignment",
                                    "type": "string",
                                    "name": "contentAlignment"
                                  }
                                ],
                                "label": "Table cell properties",
                                "type": "object",
                                "name": "tableCellProperties"
                              }
                            ]
                          },
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Magnitude",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "magnitude"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Min row height",
                                "type": "object",
                                "name": "minRowHeight"
                              }
                            ],
                            "label": "Table row properties",
                            "type": "object",
                            "name": "tableRowProperties"
                          }
                        ]
                      },
                      {
                        "name": "tableColumns",
                        "type": "array",
                        "of": "object",
                        "label": "Table columns",
                        "properties": [
                          {
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "Magnitude",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "magnitude"
                              },
                              {
                                "control_type": "text",
                                "label": "Unit",
                                "type": "string",
                                "name": "unit"
                              }
                            ],
                            "label": "Column width",
                            "type": "object",
                            "name": "columnWidth"
                          }
                        ]
                      },
                      {
                        "name": "horizontalBorderRows",
                        "type": "array",
                        "of": "object",
                        "label": "Horizontal border rows",
                        "properties": [
                          {
                            "name": "tableBorderCells",
                            "type": "array",
                            "of": "object",
                            "label": "Table border cells",
                            "properties": [
                              {
                                "properties": [],
                                "label": "Location",
                                "type": "object",
                                "name": "location"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "number",
                                                    "label": "Red",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "red"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Green",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "green"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Blue",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "blue"
                                                  }
                                                ],
                                                "label": "Rgb color",
                                                "type": "object",
                                                "name": "rgbColor"
                                              }
                                            ],
                                            "label": "Color",
                                            "type": "object",
                                            "name": "color"
                                          },
                                          {
                                            "control_type": "number",
                                            "label": "Alpha",
                                            "parse_output": "float_conversion",
                                            "type": "number",
                                            "name": "alpha"
                                          }
                                        ],
                                        "label": "Solid fill",
                                        "type": "object",
                                        "name": "solidFill"
                                      }
                                    ],
                                    "label": "Table border fill",
                                    "type": "object",
                                    "name": "tableBorderFill"
                                  },
                                  {
                                    "properties": [
                                      {
                                        "control_type": "number",
                                        "label": "Magnitude",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "magnitude"
                                      },
                                      {
                                        "control_type": "text",
                                        "label": "Unit",
                                        "type": "string",
                                        "name": "unit"
                                      }
                                    ],
                                    "label": "Weight",
                                    "type": "object",
                                    "name": "weight"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Dash style",
                                    "type": "string",
                                    "name": "dashStyle"
                                  }
                                ],
                                "label": "Table border properties",
                                "type": "object",
                                "name": "tableBorderProperties"
                              }
                            ]
                          }
                        ]
                      },
                      {
                        "name": "verticalBorderRows",
                        "type": "array",
                        "of": "object",
                        "label": "Vertical border rows",
                        "properties": [
                          {
                            "name": "tableBorderCells",
                            "type": "array",
                            "of": "object",
                            "label": "Table border cells",
                            "properties": [
                              {
                                "properties": [],
                                "label": "Location",
                                "type": "object",
                                "name": "location"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "number",
                                                    "label": "Red",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "red"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Green",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "green"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Blue",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "blue"
                                                  }
                                                ],
                                                "label": "Rgb color",
                                                "type": "object",
                                                "name": "rgbColor"
                                              }
                                            ],
                                            "label": "Color",
                                            "type": "object",
                                            "name": "color"
                                          },
                                          {
                                            "control_type": "number",
                                            "label": "Alpha",
                                            "parse_output": "float_conversion",
                                            "type": "number",
                                            "name": "alpha"
                                          }
                                        ],
                                        "label": "Solid fill",
                                        "type": "object",
                                        "name": "solidFill"
                                      }
                                    ],
                                    "label": "Table border fill",
                                    "type": "object",
                                    "name": "tableBorderFill"
                                  },
                                  {
                                    "properties": [
                                      {
                                        "control_type": "number",
                                        "label": "Magnitude",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "magnitude"
                                      },
                                      {
                                        "control_type": "text",
                                        "label": "Unit",
                                        "type": "string",
                                        "name": "unit"
                                      }
                                    ],
                                    "label": "Weight",
                                    "type": "object",
                                    "name": "weight"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Dash style",
                                    "type": "string",
                                    "name": "dashStyle"
                                  }
                                ],
                                "label": "Table border properties",
                                "type": "object",
                                "name": "tableBorderProperties"
                              }
                            ]
                          }
                        ]
                      }
                    ],
                    "label": "Table",
                    "type": "object",
                    "name": "table"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "text",
                        "label": "Shape type",
                        "type": "string",
                        "name": "shapeType"
                      },
                      {
                        "properties": [
                          {
                            "name": "textElements",
                            "type": "array",
                            "of": "object",
                            "label": "Text elements",
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "End index",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "endIndex"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "text",
                                    "label": "Content",
                                    "type": "string",
                                    "name": "content"
                                  },
                                  {
                                    "properties": [],
                                    "label": "Style",
                                    "type": "object",
                                    "name": "style"
                                  }
                                ],
                                "label": "Text run",
                                "type": "object",
                                "name": "textRun"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "control_type": "text",
                                        "label": "Direction",
                                        "type": "string",
                                        "name": "direction"
                                      }
                                    ],
                                    "label": "Style",
                                    "type": "object",
                                    "name": "style"
                                  }
                                ],
                                "label": "Paragraph marker",
                                "type": "object",
                                "name": "paragraphMarker"
                              }
                            ]
                          }
                        ],
                        "label": "Text",
                        "type": "object",
                        "name": "text"
                      },
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Shape background fill",
                            "type": "object",
                            "name": "shapeBackgroundFill"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Outline",
                            "type": "object",
                            "name": "outline"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Shadow",
                            "type": "object",
                            "name": "shadow"
                          }
                        ],
                        "label": "Shape properties",
                        "type": "object",
                        "name": "shapeProperties"
                      },
                      {
                        "properties": [
                          {
                            "control_type": "text",
                            "label": "Type",
                            "type": "string",
                            "name": "type"
                          },
                          {
                            "control_type": "text",
                            "label": "Parent object ID",
                            "type": "string",
                            "name": "parentObjectId"
                          }
                        ],
                        "label": "Placeholder",
                        "type": "object",
                        "name": "placeholder"
                      }
                    ],
                    "label": "Shape",
                    "type": "object",
                    "name": "shape"
                  }
                ]
              },
              {
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Master object ID",
                    "type": "string",
                    "name": "masterObjectId"
                  },
                  {
                    "control_type": "text",
                    "label": "Name",
                    "type": "string",
                    "name": "name"
                  },
                  {
                    "control_type": "text",
                    "label": "Display name",
                    "type": "string",
                    "name": "displayName"
                  }
                ],
                "label": "Layout properties",
                "type": "object",
                "name": "layoutProperties"
              },
              {
                "properties": [
                  {
                    "properties": [
                      {
                        "control_type": "text",
                        "label": "Property state",
                        "type": "string",
                        "name": "propertyState"
                      }
                    ],
                    "label": "Page background fill",
                    "type": "object",
                    "name": "pageBackgroundFill"
                  }
                ],
                "label": "Page properties",
                "type": "object",
                "name": "pageProperties"
              }
            ]
          },
          {
            "control_type": "text",
            "label": "Locale",
            "type": "string",
            "name": "locale"
          },
          {
            "control_type": "text",
            "label": "Revision ID",
            "type": "string",
            "name": "revisionId"
          },
          {
            "properties": [
              {
                "control_type": "text",
                "label": "Object ID",
                "type": "string",
                "name": "objectId"
              },
              {
                "control_type": "text",
                "label": "Page type",
                "type": "string",
                "name": "pageType"
              },
              {
                "name": "pageElements",
                "type": "array",
                "of": "object",
                "label": "Page elements",
                "properties": [
                  {
                    "control_type": "text",
                    "label": "Object ID",
                    "type": "string",
                    "name": "objectId"
                  },
                  {
                    "properties": [
                      {
                        "properties": [
                          {
                            "control_type": "number",
                            "label": "Magnitude",
                            "parse_output": "float_conversion",
                            "type": "number",
                            "name": "magnitude"
                          },
                          {
                            "control_type": "text",
                            "label": "Unit",
                            "type": "string",
                            "name": "unit"
                          }
                        ],
                        "label": "Width",
                        "type": "object",
                        "name": "width"
                      },
                      {
                        "properties": [
                          {
                            "control_type": "number",
                            "label": "Magnitude",
                            "parse_output": "float_conversion",
                            "type": "number",
                            "name": "magnitude"
                          },
                          {
                            "control_type": "text",
                            "label": "Unit",
                            "type": "string",
                            "name": "unit"
                          }
                        ],
                        "label": "Height",
                        "type": "object",
                        "name": "height"
                      }
                    ],
                    "label": "Size",
                    "type": "object",
                    "name": "size"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "number",
                        "label": "Scale X",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "scaleX"
                      },
                      {
                        "control_type": "number",
                        "label": "Scale Y",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "scaleY"
                      },
                      {
                        "control_type": "number",
                        "label": "Translate X",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "translateX"
                      },
                      {
                        "control_type": "number",
                        "label": "Translate Y",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "translateY"
                      },
                      {
                        "control_type": "text",
                        "label": "Unit",
                        "type": "string",
                        "name": "unit"
                      }
                    ],
                    "label": "Transform",
                    "type": "object",
                    "name": "transform"
                  },
                  {
                    "properties": [
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "control_type": "text",
                                        "label": "Theme color",
                                        "type": "string",
                                        "name": "themeColor"
                                      }
                                    ],
                                    "label": "Color",
                                    "type": "object",
                                    "name": "color"
                                  },
                                  {
                                    "control_type": "number",
                                    "label": "Alpha",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "alpha"
                                  }
                                ],
                                "label": "Solid fill",
                                "type": "object",
                                "name": "solidFill"
                              }
                            ],
                            "label": "Line fill",
                            "type": "object",
                            "name": "lineFill"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "Magnitude",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "magnitude"
                              },
                              {
                                "control_type": "text",
                                "label": "Unit",
                                "type": "string",
                                "name": "unit"
                              }
                            ],
                            "label": "Weight",
                            "type": "object",
                            "name": "weight"
                          },
                          {
                            "control_type": "text",
                            "label": "Dash style",
                            "type": "string",
                            "name": "dashStyle"
                          },
                          {
                            "control_type": "text",
                            "label": "Start arrow",
                            "type": "string",
                            "name": "startArrow"
                          },
                          {
                            "control_type": "text",
                            "label": "End arrow",
                            "type": "string",
                            "name": "endArrow"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Connected object ID",
                                "type": "string",
                                "name": "connectedObjectId"
                              },
                              {
                                "control_type": "number",
                                "label": "Connection site index",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "connectionSiteIndex"
                              }
                            ],
                            "label": "End connection",
                            "type": "object",
                            "name": "endConnection"
                          }
                        ],
                        "label": "Line properties",
                        "type": "object",
                        "name": "lineProperties"
                      },
                      {
                        "control_type": "text",
                        "label": "Line type",
                        "type": "string",
                        "name": "lineType"
                      },
                      {
                        "control_type": "text",
                        "label": "Line category",
                        "type": "string",
                        "name": "lineCategory"
                      }
                    ],
                    "label": "Line",
                    "type": "object",
                    "name": "line"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "text",
                        "label": "Content URL",
                        "type": "string",
                        "name": "contentUrl"
                      },
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "properties": [
                                          {
                                            "control_type": "text",
                                            "label": "Theme color",
                                            "type": "string",
                                            "name": "themeColor"
                                          }
                                        ],
                                        "label": "Color",
                                        "type": "object",
                                        "name": "color"
                                      },
                                      {
                                        "control_type": "number",
                                        "label": "Alpha",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "alpha"
                                      }
                                    ],
                                    "label": "Solid fill",
                                    "type": "object",
                                    "name": "solidFill"
                                  }
                                ],
                                "label": "Outline fill",
                                "type": "object",
                                "name": "outlineFill"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Magnitude",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "magnitude"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Weight",
                                "type": "object",
                                "name": "weight"
                              },
                              {
                                "control_type": "text",
                                "label": "Dash style",
                                "type": "string",
                                "name": "dashStyle"
                              },
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Outline",
                            "type": "object",
                            "name": "outline"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Type",
                                "type": "string",
                                "name": "type"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Scale X",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "scaleX"
                                  },
                                  {
                                    "control_type": "number",
                                    "label": "Scale Y",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "scaleY"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Transform",
                                "type": "object",
                                "name": "transform"
                              },
                              {
                                "control_type": "text",
                                "label": "Alignment",
                                "type": "string",
                                "name": "alignment"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Blur radius",
                                "type": "object",
                                "name": "blurRadius"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [],
                                    "label": "Rgb color",
                                    "type": "object",
                                    "name": "rgbColor"
                                  }
                                ],
                                "label": "Color",
                                "type": "object",
                                "name": "color"
                              },
                              {
                                "control_type": "number",
                                "label": "Alpha",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "alpha"
                              },
                              {
                                "control_type": "text",
                                "label": "Rotate with shape",
                                "render_input": {},
                                "parse_output": {},
                                "toggle_hint": "Select from option list",
                                "toggle_field": {
                                  "label": "Rotate with shape",
                                  "control_type": "text",
                                  "toggle_hint": "Use custom value",
                                  "type": "boolean",
                                  "name": "rotateWithShape"
                                },
                                "type": "boolean",
                                "name": "rotateWithShape"
                              },
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Shadow",
                            "type": "object",
                            "name": "shadow"
                          }
                        ],
                        "label": "Image properties",
                        "type": "object",
                        "name": "imageProperties"
                      }
                    ],
                    "label": "Image",
                    "type": "object",
                    "name": "image"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "number",
                        "label": "Rows",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "rows"
                      },
                      {
                        "control_type": "number",
                        "label": "Columns",
                        "parse_output": "float_conversion",
                        "type": "number",
                        "name": "columns"
                      },
                      {
                        "name": "tableRows",
                        "type": "array",
                        "of": "object",
                        "label": "Table rows",
                        "properties": [
                          {
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "Magnitude",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "magnitude"
                              },
                              {
                                "control_type": "text",
                                "label": "Unit",
                                "type": "string",
                                "name": "unit"
                              }
                            ],
                            "label": "Row height",
                            "type": "object",
                            "name": "rowHeight"
                          },
                          {
                            "name": "tableCells",
                            "type": "array",
                            "of": "object",
                            "label": "Table cells",
                            "properties": [
                              {
                                "properties": [],
                                "label": "Location",
                                "type": "object",
                                "name": "location"
                              },
                              {
                                "control_type": "number",
                                "label": "Row span",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "rowSpan"
                              },
                              {
                                "control_type": "number",
                                "label": "Column span",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "columnSpan"
                              },
                              {
                                "properties": [
                                  {
                                    "name": "textElements",
                                    "type": "array",
                                    "of": "object",
                                    "label": "Text elements",
                                    "properties": [
                                      {
                                        "control_type": "number",
                                        "label": "End index",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "endIndex"
                                      },
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "control_type": "number",
                                                "label": "Line spacing",
                                                "parse_output": "float_conversion",
                                                "type": "number",
                                                "name": "lineSpacing"
                                              },
                                              {
                                                "control_type": "text",
                                                "label": "Alignment",
                                                "type": "string",
                                                "name": "alignment"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Indent start",
                                                "type": "object",
                                                "name": "indentStart"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Indent end",
                                                "type": "object",
                                                "name": "indentEnd"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Space above",
                                                "type": "object",
                                                "name": "spaceAbove"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Space below",
                                                "type": "object",
                                                "name": "spaceBelow"
                                              },
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "text",
                                                    "label": "Unit",
                                                    "type": "string",
                                                    "name": "unit"
                                                  }
                                                ],
                                                "label": "Indent first line",
                                                "type": "object",
                                                "name": "indentFirstLine"
                                              },
                                              {
                                                "control_type": "text",
                                                "label": "Direction",
                                                "type": "string",
                                                "name": "direction"
                                              },
                                              {
                                                "control_type": "text",
                                                "label": "Spacing mode",
                                                "type": "string",
                                                "name": "spacingMode"
                                              }
                                            ],
                                            "label": "Style",
                                            "type": "object",
                                            "name": "style"
                                          }
                                        ],
                                        "label": "Paragraph marker",
                                        "type": "object",
                                        "name": "paragraphMarker"
                                      }
                                    ]
                                  }
                                ],
                                "label": "Text",
                                "type": "object",
                                "name": "text"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "control_type": "text",
                                        "label": "Property state",
                                        "type": "string",
                                        "name": "propertyState"
                                      },
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "number",
                                                    "label": "Red",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "red"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Green",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "green"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Blue",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "blue"
                                                  }
                                                ],
                                                "label": "Rgb color",
                                                "type": "object",
                                                "name": "rgbColor"
                                              }
                                            ],
                                            "label": "Color",
                                            "type": "object",
                                            "name": "color"
                                          },
                                          {
                                            "control_type": "number",
                                            "label": "Alpha",
                                            "parse_output": "float_conversion",
                                            "type": "number",
                                            "name": "alpha"
                                          }
                                        ],
                                        "label": "Solid fill",
                                        "type": "object",
                                        "name": "solidFill"
                                      }
                                    ],
                                    "label": "Table cell background fill",
                                    "type": "object",
                                    "name": "tableCellBackgroundFill"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Content alignment",
                                    "type": "string",
                                    "name": "contentAlignment"
                                  }
                                ],
                                "label": "Table cell properties",
                                "type": "object",
                                "name": "tableCellProperties"
                              }
                            ]
                          },
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Magnitude",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "magnitude"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Unit",
                                    "type": "string",
                                    "name": "unit"
                                  }
                                ],
                                "label": "Min row height",
                                "type": "object",
                                "name": "minRowHeight"
                              }
                            ],
                            "label": "Table row properties",
                            "type": "object",
                            "name": "tableRowProperties"
                          }
                        ]
                      },
                      {
                        "name": "tableColumns",
                        "type": "array",
                        "of": "object",
                        "label": "Table columns",
                        "properties": [
                          {
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "Magnitude",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "magnitude"
                              },
                              {
                                "control_type": "text",
                                "label": "Unit",
                                "type": "string",
                                "name": "unit"
                              }
                            ],
                            "label": "Column width",
                            "type": "object",
                            "name": "columnWidth"
                          }
                        ]
                      },
                      {
                        "name": "horizontalBorderRows",
                        "type": "array",
                        "of": "object",
                        "label": "Horizontal border rows",
                        "properties": [
                          {
                            "name": "tableBorderCells",
                            "type": "array",
                            "of": "object",
                            "label": "Table border cells",
                            "properties": [
                              {
                                "properties": [],
                                "label": "Location",
                                "type": "object",
                                "name": "location"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "number",
                                                    "label": "Red",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "red"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Green",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "green"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Blue",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "blue"
                                                  }
                                                ],
                                                "label": "Rgb color",
                                                "type": "object",
                                                "name": "rgbColor"
                                              }
                                            ],
                                            "label": "Color",
                                            "type": "object",
                                            "name": "color"
                                          },
                                          {
                                            "control_type": "number",
                                            "label": "Alpha",
                                            "parse_output": "float_conversion",
                                            "type": "number",
                                            "name": "alpha"
                                          }
                                        ],
                                        "label": "Solid fill",
                                        "type": "object",
                                        "name": "solidFill"
                                      }
                                    ],
                                    "label": "Table border fill",
                                    "type": "object",
                                    "name": "tableBorderFill"
                                  },
                                  {
                                    "properties": [
                                      {
                                        "control_type": "number",
                                        "label": "Magnitude",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "magnitude"
                                      },
                                      {
                                        "control_type": "text",
                                        "label": "Unit",
                                        "type": "string",
                                        "name": "unit"
                                      }
                                    ],
                                    "label": "Weight",
                                    "type": "object",
                                    "name": "weight"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Dash style",
                                    "type": "string",
                                    "name": "dashStyle"
                                  }
                                ],
                                "label": "Table border properties",
                                "type": "object",
                                "name": "tableBorderProperties"
                              }
                            ]
                          }
                        ]
                      },
                      {
                        "name": "verticalBorderRows",
                        "type": "array",
                        "of": "object",
                        "label": "Vertical border rows",
                        "properties": [
                          {
                            "name": "tableBorderCells",
                            "type": "array",
                            "of": "object",
                            "label": "Table border cells",
                            "properties": [
                              {
                                "properties": [],
                                "label": "Location",
                                "type": "object",
                                "name": "location"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "properties": [
                                          {
                                            "properties": [
                                              {
                                                "properties": [
                                                  {
                                                    "control_type": "number",
                                                    "label": "Red",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "red"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Green",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "green"
                                                  },
                                                  {
                                                    "control_type": "number",
                                                    "label": "Blue",
                                                    "parse_output": "float_conversion",
                                                    "type": "number",
                                                    "name": "blue"
                                                  }
                                                ],
                                                "label": "Rgb color",
                                                "type": "object",
                                                "name": "rgbColor"
                                              }
                                            ],
                                            "label": "Color",
                                            "type": "object",
                                            "name": "color"
                                          },
                                          {
                                            "control_type": "number",
                                            "label": "Alpha",
                                            "parse_output": "float_conversion",
                                            "type": "number",
                                            "name": "alpha"
                                          }
                                        ],
                                        "label": "Solid fill",
                                        "type": "object",
                                        "name": "solidFill"
                                      }
                                    ],
                                    "label": "Table border fill",
                                    "type": "object",
                                    "name": "tableBorderFill"
                                  },
                                  {
                                    "properties": [
                                      {
                                        "control_type": "number",
                                        "label": "Magnitude",
                                        "parse_output": "float_conversion",
                                        "type": "number",
                                        "name": "magnitude"
                                      },
                                      {
                                        "control_type": "text",
                                        "label": "Unit",
                                        "type": "string",
                                        "name": "unit"
                                      }
                                    ],
                                    "label": "Weight",
                                    "type": "object",
                                    "name": "weight"
                                  },
                                  {
                                    "control_type": "text",
                                    "label": "Dash style",
                                    "type": "string",
                                    "name": "dashStyle"
                                  }
                                ],
                                "label": "Table border properties",
                                "type": "object",
                                "name": "tableBorderProperties"
                              }
                            ]
                          }
                        ]
                      }
                    ],
                    "label": "Table",
                    "type": "object",
                    "name": "table"
                  },
                  {
                    "properties": [
                      {
                        "control_type": "text",
                        "label": "Shape type",
                        "type": "string",
                        "name": "shapeType"
                      },
                      {
                        "properties": [
                          {
                            "name": "textElements",
                            "type": "array",
                            "of": "object",
                            "label": "Text elements",
                            "properties": [
                              {
                                "control_type": "number",
                                "label": "End index",
                                "parse_output": "float_conversion",
                                "type": "number",
                                "name": "endIndex"
                              },
                              {
                                "properties": [
                                  {
                                    "control_type": "text",
                                    "label": "Content",
                                    "type": "string",
                                    "name": "content"
                                  },
                                  {
                                    "properties": [],
                                    "label": "Style",
                                    "type": "object",
                                    "name": "style"
                                  }
                                ],
                                "label": "Text run",
                                "type": "object",
                                "name": "textRun"
                              },
                              {
                                "properties": [
                                  {
                                    "properties": [
                                      {
                                        "control_type": "text",
                                        "label": "Direction",
                                        "type": "string",
                                        "name": "direction"
                                      }
                                    ],
                                    "label": "Style",
                                    "type": "object",
                                    "name": "style"
                                  }
                                ],
                                "label": "Paragraph marker",
                                "type": "object",
                                "name": "paragraphMarker"
                              }
                            ]
                          }
                        ],
                        "label": "Text",
                        "type": "object",
                        "name": "text"
                      },
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Shape background fill",
                            "type": "object",
                            "name": "shapeBackgroundFill"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Outline",
                            "type": "object",
                            "name": "outline"
                          },
                          {
                            "properties": [
                              {
                                "control_type": "text",
                                "label": "Property state",
                                "type": "string",
                                "name": "propertyState"
                              }
                            ],
                            "label": "Shadow",
                            "type": "object",
                            "name": "shadow"
                          }
                        ],
                        "label": "Shape properties",
                        "type": "object",
                        "name": "shapeProperties"
                      },
                      {
                        "properties": [
                          {
                            "control_type": "text",
                            "label": "Type",
                            "type": "string",
                            "name": "type"
                          },
                          {
                            "control_type": "text",
                            "label": "Parent object ID",
                            "type": "string",
                            "name": "parentObjectId"
                          }
                        ],
                        "label": "Placeholder",
                        "type": "object",
                        "name": "placeholder"
                      }
                    ],
                    "label": "Shape",
                    "type": "object",
                    "name": "shape"
                  }
                ]
              },
              {
                "properties": [
                  {
                    "properties": [
                      {
                        "control_type": "text",
                        "label": "Property state",
                        "type": "string",
                        "name": "propertyState"
                      },
                      {
                        "properties": [
                          {
                            "properties": [
                              {
                                "properties": [
                                  {
                                    "control_type": "number",
                                    "label": "Red",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "red"
                                  },
                                  {
                                    "control_type": "number",
                                    "label": "Green",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "green"
                                  },
                                  {
                                    "control_type": "number",
                                    "label": "Blue",
                                    "parse_output": "float_conversion",
                                    "type": "number",
                                    "name": "blue"
                                  }
                                ],
                                "label": "Rgb color",
                                "type": "object",
                                "name": "rgbColor"
                              }
                            ],
                            "label": "Color",
                            "type": "object",
                            "name": "color"
                          },
                          {
                            "control_type": "number",
                            "label": "Alpha",
                            "parse_output": "float_conversion",
                            "type": "number",
                            "name": "alpha"
                          }
                        ],
                        "label": "Solid fill",
                        "type": "object",
                        "name": "solidFill"
                      }
                    ],
                    "label": "Page background fill",
                    "type": "object",
                    "name": "pageBackgroundFill"
                  },
                  {
                    "properties": [
                      {
                        "name": "colors",
                        "type": "array",
                        "of": "object",
                        "label": "Colors",
                        "properties": [
                          {
                            "control_type": "text",
                            "label": "Type",
                            "type": "string",
                            "name": "type"
                          },
                          {
                            "properties": [],
                            "label": "Color",
                            "type": "object",
                            "name": "color"
                          }
                        ]
                      }
                    ],
                    "label": "Color scheme",
                    "type": "object",
                    "name": "colorScheme"
                  }
                ],
                "label": "Page properties",
                "type": "object",
                "name": "pageProperties"
              }
            ],
            "label": "Notes master",
            "type": "object",
            "name": "notesMaster"
          }
        ]
      end
    },
    update_response: {
      fields: lambda do
        [
          {
            "name": "replies",
            "type": "array",
            "of": "object",
            "label": "Replies",
            "properties": [
              {
                "properties": [
                  {
                    "control_type": "number",
                    "label": "Occurrences changed",
                    "parse_output": "float_conversion",
                    "type": "number",
                    "name": "occurrencesChanged"
                  }
                ],
                "label": "Replace all text",
                "type": "object",
                "name": "replaceAllText"
              }
            ]
          },
          {
            "name": "presentationId"
          },
          {
            "name": "writeControl",
            "type": "object",
            "properties": [
              {
                "name": "requiredRevisionId"
              }
            ]
          }
        ]
      end
    }
  }
}
