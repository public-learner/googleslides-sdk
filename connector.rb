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

  methods: {
    ##############################################################
    # Helper methods                                             #
    ##############################################################
    # This method is for Custom action
    make_schema_builder_fields_sticky: lambda do |schema|
      schema.map do |field|
        if field['properties'].present?
          field['properties'] = call('make_schema_builder_fields_sticky',
                                     field['properties'])
        end
        field['sticky'] = true

        field
      end
    end,

    # Formats input/output schema to replace any special characters in name,
    # without changing other attributes (method required for custom action)
    format_schema: lambda do |input|
      input&.map do |field|
        if (props = field[:properties])
          field[:properties] = call('format_schema', props)
        elsif (props = field['properties'])
          field['properties'] = call('format_schema', props)
        end
        if (name = field[:name])
          field[:label] = field[:label].presence || name.labelize
          field[:name] = name
            .gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        elsif (name = field['name'])
          field['label'] = field['label'].presence || name.labelize
          field['name'] = name
            .gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
        end

        field
      end
    end,

    # Formats payload to inject any special characters that previously removed
    format_payload: lambda do |payload|
      if payload.is_a?(Array)
        payload.map do |array_value|
          call('format_payload', array_value)
        end
      elsif payload.is_a?(Hash)
        payload.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/__\w+__/) do |string|
            string.gsub(/__/, '').decode_hex.as_utf8
          end
          if value.is_a?(Array) || value.is_a?(Hash)
            value = call('format_payload', value)
          end
          hash[key] = value
        end
      end
    end,

    # Formats response to replace any special characters with valid strings
    # (method required for custom action)
    format_response: lambda do |response|
      response = response&.compact unless response.is_a?(String) || response
      if response.is_a?(Array)
        response.map do |array_value|
          call('format_response', array_value)
        end
      elsif response.is_a?(Hash)
        response.each_with_object({}) do |(key, value), hash|
          key = key.gsub(/\W/) { |spl_chr| "__#{spl_chr.encode_hex}__" }
          if value.is_a?(Array) || value.is_a?(Hash)
            value = call('format_response', value)
          end
          hash[key] = value
        end
      else
        response
      end
    end
  },
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
    },
    custom_action: {
      subtitle: 'Build your own Google Slides action with a HTTP request',

      description: lambda do |object_value, _object_label|
        "<span class='provider'>" \
          "#{object_value[:action_name] || 'Custom action'}</span> in " \
          "<span class='provider'>Google Slides</span>"
      end,

      help: {
        body: 'Build your own Google Slides action with a HTTP request. ' \
        'The request will be authorized with your {APP} connection.',
        learn_more_url: 'https://developers.google.com/slides/reference/rest',
        learn_more_text: 'Google Slides API documentation'
      },

      config_fields: [
        {
          name: 'action_name',
          hint: "Give this action you're building a descriptive name, e.g. " \
          'create record, get record',
          default: 'Custom action',
          optional: false,
          schema_neutral: true
        },
        {
          name: 'verb',
          label: 'Method',
          hint: 'Select HTTP method of the request',
          optional: false,
          control_type: 'select',
          pick_list: %w[get post put patch options delete]
          .map { |verb| [verb.upcase, verb] }
        }
      ],

      input_fields: lambda do |object_definition|
        object_definition['custom_action_input']
      end,

      execute: lambda do |_connection, input|
        verb = input['verb']
        if %w[get post put patch options delete].exclude?(verb)
          error("#{verb.upcase} not supported")
        end
        path = input['path']
        data = input.dig('input', 'data') || {}
        if input['request_type'] == 'multipart'
          data = data.each_with_object({}) do |(key, val), hash|
            hash[key] = if val.is_a?(Hash)
                          [val[:file_content],
                           val[:content_type],
                           val[:original_filename]]
                        else
                          val
                        end
          end
        end
        request_headers = input['request_headers']
        &.each_with_object({}) do |item, hash|
          hash[item['key']] = item['value']
        end || {}
        request = case verb
                  when 'get'
                    get(path, data)
                  when 'post'
                    if input['request_type'] == 'raw'
                      post(path).request_body(data)
                    else
                      post(path, data)
                    end
                  when 'put'
                    if input['request_type'] == 'raw'
                      put(path).request_body(data)
                    else
                      put(path, data)
                    end
                  when 'patch'
                    if input['request_type'] == 'raw'
                      patch(path).request_body(data)
                    else
                      patch(path, data)
                    end
                  when 'options'
                    options(path, data)
                  when 'delete'
                    delete(path, data)
                  end.headers(request_headers)
                  request = case input['request_type']
                            when 'url_encoded_form'
                              request.request_format_www_form_urlencoded
                            when 'multipart'
                              request.request_format_multipart_form
                            else
                              request
                            end
                  response =
                    if input['response_type'] == 'raw'
                      request.response_format_raw
                    else
                      request
                    end
                      .after_error_response(/.*/) do |code, body, headers, message|
                      error({ code: code, message: message, body: body, headers: headers }
                        .to_json)
                    end

                    response.after_response do |_code, res_body, res_headers|
                      {
                        body: res_body ? call('format_response', res_body) : nil,
                        headers: res_headers
                      }
                    end
      end,

      output_fields: lambda do |object_definition|
        object_definition['custom_action_output']
      end
    }
  },
  object_definitions: {
    custom_action_input: {
      fields: lambda do |_connection, config_fields|
        verb = config_fields['verb']
        input_schema = parse_json(config_fields.dig('input', 'schema') || '[]')
        data_props =
          input_schema.map do |field|
            if config_fields['request_type'] == 'multipart' &&
                field['binary_content'] == 'true'
              field['type'] = 'object'
              field['properties'] = [
                { name: 'file_content', optional: false },
                {
                  name: 'content_type',
                  default: 'text/plain',
                  sticky: true
                },
                { name: 'original_filename', sticky: true }
              ]
            end
            field
          end
        data_props = call('make_schema_builder_fields_sticky', data_props)
        input_data =
          if input_schema.present?
            if input_schema.dig(0, 'type') == 'array' &&
                input_schema.dig(0, 'details', 'fake_array')
              {
                name: 'data',
                type: 'array',
                of: 'object',
                properties: data_props.dig(0, 'properties')
              }
            else
              { name: 'data', type: 'object', properties: data_props }
            end
          end

        [
          {
            name: 'path',
            hint: 'Base URI is <b>' \
            'https://docs.googleapis.com' \
            '</b> - path will be appended to this URI. Use absolute URI to ' \
            'override this base URI.',
            optional: false
          },
          if %w[post put patch].include?(verb)
            {
              name: 'request_type',
              default: 'json',
              sticky: true,
              extends_schema: true,
              control_type: 'select',
              pick_list: [
                ['JSON request body', 'json'],
                ['URL encoded form', 'url_encoded_form'],
                ['Mutipart form', 'multipart'],
                ['Raw request body', 'raw']
              ]
            }
          end,
          {
            name: 'response_type',
            default: 'json',
            sticky: false,
            extends_schema: true,
            control_type: 'select',
            pick_list: [['JSON response', 'json'], ['Raw response', 'raw']]
          },
          if %w[get options delete].include?(verb)
            {
              name: 'input',
              label: 'Request URL parameters',
              sticky: true,
              add_field_label: 'Add URL parameter',
              control_type: 'form-schema-builder',
              type: 'object',
              properties: [
                {
                  name: 'schema',
                  sticky: input_schema.blank?,
                  extends_schema: true
                },
                input_data
              ].compact
            }
          else
            {
              name: 'input',
              label: 'Request body parameters',
              sticky: true,
              type: 'object',
              properties:
              if config_fields['request_type'] == 'raw'
                [{
                  name: 'data',
                  sticky: true,
                  control_type: 'text-area',
                  type: 'string'
                }]
            else
              [
                {
                  name: 'schema',
                  sticky: input_schema.blank?,
                  extends_schema: true,
                  schema_neutral: true,
                  control_type: 'schema-designer',
                  sample_data_type: 'json_input',
                  custom_properties:
                  if config_fields['request_type'] == 'multipart'
                    [{
                      name: 'binary_content',
                      label: 'File attachment',
                      default: false,
                      optional: true,
                      sticky: true,
                      render_input: 'boolean_conversion',
                      parse_output: 'boolean_conversion',
                      control_type: 'checkbox',
                      type: 'boolean'
                    }]
                end
                },
                input_data
              ].compact
            end
            }
          end,
          {
            name: 'request_headers',
            sticky: false,
            extends_schema: true,
            control_type: 'key_value',
            empty_list_title: 'Does this HTTP request require headers?',
            empty_list_text: 'Refer to the API documentation and add ' \
            'required headers to this HTTP request',
            item_label: 'Header',
            type: 'array',
            of: 'object',
            properties: [{ name: 'key' }, { name: 'value' }]
          },
          unless config_fields['response_type'] == 'raw'
            {
              name: 'output',
              label: 'Response body',
              sticky: true,
              extends_schema: true,
              schema_neutral: true,
              control_type: 'schema-designer',
              sample_data_type: 'json_input'
            }
          end,
          {
            name: 'response_headers',
            sticky: false,
            extends_schema: true,
            schema_neutral: true,
            control_type: 'schema-designer',
            sample_data_type: 'json_input'
          }
        ].compact
      end
    },

    custom_action_output: {
      fields: lambda do |_connection, config_fields|
        response_body = { name: 'body' }

        [
          if config_fields['response_type'] == 'raw'
            response_body
        elsif (output = config_fields['output'])
          output_schema = call('format_schema', parse_json(output))
          if output_schema.dig(0, 'type') == 'array' &&
              output_schema.dig(0, 'details', 'fake_array')
            response_body[:type] = 'array'
            response_body[:properties] = output_schema.dig(0, 'properties')
          else
            response_body[:type] = 'object'
            response_body[:properties] = output_schema
          end

          response_body
        end,
        if (headers = config_fields['response_headers'])
          header_props = parse_json(headers)&.map do |field|
            if field[:name].present?
              field[:name] = field[:name].gsub(/\W/, '_').downcase
            elsif field['name'].present?
              field['name'] = field['name'].gsub(/\W/, '_').downcase
            end
            field
          end

          { name: 'headers', type: 'object', properties: header_props }
        end
        ].compact
      end
    },
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
