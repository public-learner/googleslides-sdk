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
    # get_presentation: {
    #   title: "Get Presentation",
    #   input_fields: lambda do |_object_definitions|
    #     [
    #       {
    #         name: "presentation_id",
    #         optional: false
    #       }
    #     ]
    #   end,
    #   execute: lambda do |connection, input|
    #     get("/v1/presentations/#{input["presentation_id"]}")
    #   end,
    #   output_fields: lambda do |object_definitions|
    #     object_definitions["document"]
    #   end
    # },
    update_presentation: {
      title: "Update Presentation",
      input_fields: lambda do |object_definitions|
        [
          {
            name: "presentation_id",
            optional: false
          },
          {
            name: "requests",
            optional: false,
            type: :array,
            of: :object,
            properties: object_definitions["replace_all_text"]
          }
        ]
      end,
      execute: lambda do |connection, input|
        input["writeControl"] = {
          "requiredRevisionId": get("/v1/presentations/#{input["presentation_id"]}")["revisionId"]
        }
        response = post("/v1/presentations/#{input["presentation_id"]}:batchUpdate").
          payload(input)
        # response["doc_url"] = "https://docs.google.com/document/d/#{response["documentId"]}/edit?usp=drivesdk"
        response
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
            "optional": false,
            "type": "object",
            "name": "replaceAllText"
          }
        ]
      end
    },
    document: {
      fields: lambda do
				[
				  {
				    "control_type": "text",
				    "label": "Title",
				    "type": "string",
				    "name": "title"
				  },
				  {
				    "properties": [
				      {
				        "name": "content",
				        "type": "array",
				        "of": "object",
				        "label": "Content",
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
				                    "control_type": "text",
				                    "label": "Column separator style",
				                    "type": "string",
				                    "name": "columnSeparatorStyle"
				                  },
				                  {
				                    "control_type": "text",
				                    "label": "Content direction",
				                    "type": "string",
				                    "name": "contentDirection"
				                  }
				                ],
				                "label": "Section style",
				                "type": "object",
				                "name": "sectionStyle"
				              }
				            ],
				            "label": "Section break",
				            "type": "object",
				            "name": "sectionBreak"
				          }
				        ]
				      }
				    ],
				    "label": "Body",
				    "type": "object",
				    "name": "body"
				  },
				  {
				    "properties": [
				      {
				        "properties": [
				          {
				            "properties": [],
				            "label": "Color",
				            "type": "object",
				            "name": "color"
				          }
				        ],
				        "label": "Background",
				        "type": "object",
				        "name": "background"
				      },
				      {
				        "control_type": "number",
				        "label": "Page number start",
				        "parse_output": "float_conversion",
				        "type": "number",
				        "name": "pageNumberStart"
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
				        "label": "Margin top",
				        "type": "object",
				        "name": "marginTop"
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
				        "label": "Margin bottom",
				        "type": "object",
				        "name": "marginBottom"
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
				        "label": "Margin right",
				        "type": "object",
				        "name": "marginRight"
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
				        "label": "Margin left",
				        "type": "object",
				        "name": "marginLeft"
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
				            "label": "Height",
				            "type": "object",
				            "name": "height"
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
				            "label": "Width",
				            "type": "object",
				            "name": "width"
				          }
				        ],
				        "label": "Page size",
				        "type": "object",
				        "name": "pageSize"
				      }
				    ],
				    "label": "Document style",
				    "type": "object",
				    "name": "documentStyle"
				  },
				  {
				    "properties": [
				      {
				        "name": "styles",
				        "type": "array",
				        "of": "object",
				        "label": "Styles",
				        "properties": [
				          {
				            "control_type": "text",
				            "label": "Named style type",
				            "type": "string",
				            "name": "namedStyleType"
				          },
				          {
				            "properties": [
				              {
				                "control_type": "text",
				                "label": "Bold",
				                "render_input": {},
				                "parse_output": {},
				                "toggle_hint": "Select from option list",
				                "toggle_field": {
				                  "label": "Bold",
				                  "control_type": "text",
				                  "toggle_hint": "Use custom value",
				                  "type": "boolean",
				                  "name": "bold"
				                },
				                "type": "boolean",
				                "name": "bold"
				              },
				              {
				                "control_type": "text",
				                "label": "Italic",
				                "render_input": {},
				                "parse_output": {},
				                "toggle_hint": "Select from option list",
				                "toggle_field": {
				                  "label": "Italic",
				                  "control_type": "text",
				                  "toggle_hint": "Use custom value",
				                  "type": "boolean",
				                  "name": "italic"
				                },
				                "type": "boolean",
				                "name": "italic"
				              },
				              {
				                "control_type": "text",
				                "label": "Underline",
				                "render_input": {},
				                "parse_output": {},
				                "toggle_hint": "Select from option list",
				                "toggle_field": {
				                  "label": "Underline",
				                  "control_type": "text",
				                  "toggle_hint": "Use custom value",
				                  "type": "boolean",
				                  "name": "underline"
				                },
				                "type": "boolean",
				                "name": "underline"
				              },
				              {
				                "control_type": "text",
				                "label": "Strikethrough",
				                "render_input": {},
				                "parse_output": {},
				                "toggle_hint": "Select from option list",
				                "toggle_field": {
				                  "label": "Strikethrough",
				                  "control_type": "text",
				                  "toggle_hint": "Use custom value",
				                  "type": "boolean",
				                  "name": "strikethrough"
				                },
				                "type": "boolean",
				                "name": "strikethrough"
				              },
				              {
				                "control_type": "text",
				                "label": "Small caps",
				                "render_input": {},
				                "parse_output": {},
				                "toggle_hint": "Select from option list",
				                "toggle_field": {
				                  "label": "Small caps",
				                  "control_type": "text",
				                  "toggle_hint": "Use custom value",
				                  "type": "boolean",
				                  "name": "smallCaps"
				                },
				                "type": "boolean",
				                "name": "smallCaps"
				              },
				              {
				                "properties": [],
				                "label": "Background color",
				                "type": "object",
				                "name": "backgroundColor"
				              },
				              {
				                "properties": [
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
				                  }
				                ],
				                "label": "Foreground color",
				                "type": "object",
				                "name": "foregroundColor"
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
				                "label": "Font size",
				                "type": "object",
				                "name": "fontSize"
				              },
				              {
				                "properties": [
				                  {
				                    "control_type": "text",
				                    "label": "Font family",
				                    "type": "string",
				                    "name": "fontFamily"
				                  },
				                  {
				                    "control_type": "number",
				                    "label": "Weight",
				                    "parse_output": "float_conversion",
				                    "type": "number",
				                    "name": "weight"
				                  }
				                ],
				                "label": "Weighted font family",
				                "type": "object",
				                "name": "weightedFontFamily"
				              },
				              {
				                "control_type": "text",
				                "label": "Baseline offset",
				                "type": "string",
				                "name": "baselineOffset"
				              }
				            ],
				            "label": "Text style",
				            "type": "object",
				            "name": "textStyle"
				          },
				          {
				            "properties": [
				              {
				                "control_type": "text",
				                "label": "Named style type",
				                "type": "string",
				                "name": "namedStyleType"
				              },
				              {
				                "control_type": "text",
				                "label": "Alignment",
				                "type": "string",
				                "name": "alignment"
				              },
				              {
				                "control_type": "number",
				                "label": "Line spacing",
				                "parse_output": "float_conversion",
				                "type": "number",
				                "name": "lineSpacing"
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
				                    "properties": [],
				                    "label": "Color",
				                    "type": "object",
				                    "name": "color"
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
				                    "label": "Width",
				                    "type": "object",
				                    "name": "width"
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
				                    "label": "Padding",
				                    "type": "object",
				                    "name": "padding"
				                  },
				                  {
				                    "control_type": "text",
				                    "label": "Dash style",
				                    "type": "string",
				                    "name": "dashStyle"
				                  }
				                ],
				                "label": "Border between",
				                "type": "object",
				                "name": "borderBetween"
				              },
				              {
				                "properties": [
				                  {
				                    "properties": [],
				                    "label": "Color",
				                    "type": "object",
				                    "name": "color"
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
				                    "label": "Width",
				                    "type": "object",
				                    "name": "width"
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
				                    "label": "Padding",
				                    "type": "object",
				                    "name": "padding"
				                  },
				                  {
				                    "control_type": "text",
				                    "label": "Dash style",
				                    "type": "string",
				                    "name": "dashStyle"
				                  }
				                ],
				                "label": "Border top",
				                "type": "object",
				                "name": "borderTop"
				              },
				              {
				                "properties": [
				                  {
				                    "properties": [],
				                    "label": "Color",
				                    "type": "object",
				                    "name": "color"
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
				                    "label": "Width",
				                    "type": "object",
				                    "name": "width"
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
				                    "label": "Padding",
				                    "type": "object",
				                    "name": "padding"
				                  },
				                  {
				                    "control_type": "text",
				                    "label": "Dash style",
				                    "type": "string",
				                    "name": "dashStyle"
				                  }
				                ],
				                "label": "Border bottom",
				                "type": "object",
				                "name": "borderBottom"
				              },
				              {
				                "properties": [
				                  {
				                    "properties": [],
				                    "label": "Color",
				                    "type": "object",
				                    "name": "color"
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
				                    "label": "Width",
				                    "type": "object",
				                    "name": "width"
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
				                    "label": "Padding",
				                    "type": "object",
				                    "name": "padding"
				                  },
				                  {
				                    "control_type": "text",
				                    "label": "Dash style",
				                    "type": "string",
				                    "name": "dashStyle"
				                  }
				                ],
				                "label": "Border left",
				                "type": "object",
				                "name": "borderLeft"
				              },
				              {
				                "properties": [
				                  {
				                    "properties": [],
				                    "label": "Color",
				                    "type": "object",
				                    "name": "color"
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
				                    "label": "Width",
				                    "type": "object",
				                    "name": "width"
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
				                    "label": "Padding",
				                    "type": "object",
				                    "name": "padding"
				                  },
				                  {
				                    "control_type": "text",
				                    "label": "Dash style",
				                    "type": "string",
				                    "name": "dashStyle"
				                  }
				                ],
				                "label": "Border right",
				                "type": "object",
				                "name": "borderRight"
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
				                "control_type": "text",
				                "label": "Keep lines together",
				                "render_input": {},
				                "parse_output": {},
				                "toggle_hint": "Select from option list",
				                "toggle_field": {
				                  "label": "Keep lines together",
				                  "control_type": "text",
				                  "toggle_hint": "Use custom value",
				                  "type": "boolean",
				                  "name": "keepLinesTogether"
				                },
				                "type": "boolean",
				                "name": "keepLinesTogether"
				              },
				              {
				                "control_type": "text",
				                "label": "Keep with next",
				                "render_input": {},
				                "parse_output": {},
				                "toggle_hint": "Select from option list",
				                "toggle_field": {
				                  "label": "Keep with next",
				                  "control_type": "text",
				                  "toggle_hint": "Use custom value",
				                  "type": "boolean",
				                  "name": "keepWithNext"
				                },
				                "type": "boolean",
				                "name": "keepWithNext"
				              },
				              {
				                "control_type": "text",
				                "label": "Avoid widow and orphan",
				                "render_input": {},
				                "parse_output": {},
				                "toggle_hint": "Select from option list",
				                "toggle_field": {
				                  "label": "Avoid widow and orphan",
				                  "control_type": "text",
				                  "toggle_hint": "Use custom value",
				                  "type": "boolean",
				                  "name": "avoidWidowAndOrphan"
				                },
				                "type": "boolean",
				                "name": "avoidWidowAndOrphan"
				              },
				              {
				                "properties": [
				                  {
				                    "properties": [],
				                    "label": "Background color",
				                    "type": "object",
				                    "name": "backgroundColor"
				                  }
				                ],
				                "label": "Shading",
				                "type": "object",
				                "name": "shading"
				              }
				            ],
				            "label": "Paragraph style",
				            "type": "object",
				            "name": "paragraphStyle"
				          }
				        ]
				      }
				    ],
				    "label": "Named styles",
				    "type": "object",
				    "name": "namedStyles"
				  },
				  {
				    "control_type": "text",
				    "label": "Revision ID",
				    "type": "string",
				    "name": "revisionId"
				  },
				  {
				    "control_type": "text",
				    "label": "Suggestions view mode",
				    "type": "string",
				    "name": "suggestionsViewMode"
				  },
				  {
				    "control_type": "text",
				    "label": "Document ID",
				    "type": "string",
				    "name": "documentId"
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
				    "properties": [
				      {
				        "control_type": "text",
				        "label": "Required revision ID",
				        "type": "string",
				        "name": "requiredRevisionId"
				      }
				    ],
				    "label": "Write control",
				    "type": "object",
				    "name": "writeControl"
				  },
				  {
				    "name": "documentId"
				  },
          {
            name: "doc_url"
          }
				]
      end
    }
  }
}
