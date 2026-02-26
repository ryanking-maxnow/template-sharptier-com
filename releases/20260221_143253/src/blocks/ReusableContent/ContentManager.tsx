'use client'

import { Template } from '@/payload-types'
import { useConfig, useForm, useFormFields } from '@payloadcms/ui'
import { UIFieldClientProps } from 'payload'
import { useEffect, useRef } from 'react'

export const ContentManager: React.FC<UIFieldClientProps> = (props) => {
  const { path, schemaPath } = props

  const isFetching = useRef(false)
  const {
    config: {
      serverURL,
      routes: { api },
    },
  } = useConfig()

  const { addFieldRow } = useForm()

  // We're constructing the paths of the other fields in this block, note that they will be relative to this field's path
  const checkboxPath = `${path.replace('contentManager', 'useTemplateValues')}`
  const templatePath = `${path.replace('contentManager', 'template')}`
  const contentPath = `${path.replace('contentManager', 'content')}`
  // The schema path is important to get the right config for our blocks
  const contentSchemaPath = schemaPath ? `${schemaPath.replace('contentManager', 'content')}` : null

  const {
    checkboxField: { value: checkboxValue },
    templateField: { value: templateValue },
    contentField,
    dispatchField,
  } = useFormFields(([fields, dispatch]) => {
    return {
      checkboxField: fields[checkboxPath],
      templateField: fields[templatePath],
      contentField: fields[contentPath],
      dispatchField: dispatch,
    }
  })

  const contentValue = contentField?.value as number | undefined

  useEffect(() => {
    if (templateValue) {
      // If the checkbox is checked and we have content, remove all blocks from the content field
      if (typeof contentValue !== 'undefined' && contentValue && checkboxValue) {
        // Cant remove the field directly, so we loop through the rows and remove them
        for (let i = contentValue - 1; i >= 0; i--) {
          dispatchField({
            type: 'REMOVE_ROW',
            path: contentPath,
            rowIndex: i,
          })
        }
      }
      // Otherwise start fetching the template content and populating the content field
      if (!contentValue && !checkboxValue) {
        if (!isFetching.current) {
          const fetchTemplateContent = async () => {
            const apiURL = serverURL ? `${serverURL}${api}` : api
            const res = await fetch(`${apiURL}/templates/${templateValue}?depth=0`, {
              method: 'get',
              credentials: 'include',
              headers: {
                'Content-Type': 'application/json',
              },
            })
            const templateDoc: Template = await res.json()
            if (templateDoc && 'content' in templateDoc) {
              const templateContent = templateDoc.content

              if (
                contentSchemaPath &&
                templateDoc &&
                Array.isArray(templateContent) &&
                templateContent.length > 0
              ) {
                // For each of our blocks, we loop through them and add them to our content field
                for (let i = 0; i < templateContent.length; i++) {
                  switch (templateContent[i].blockType) {
                    case 'content': {
                      addFieldRow({
                        // The sub field state is the actual content of the block
                        // It needs an object of the state of each field in the block, in this case 'richText'
                        subFieldState: {
                          richText: {
                            value: templateContent[i].richText || null,
                          },
                        },
                        path: contentPath,
                        blockType: templateContent[i].blockType,
                        rowIndex: i,
                        schemaPath: contentSchemaPath,
                      })
                      break
                    }
                    // Add more block types here as needed
                    default:
                      console.log('Unknown block type:', templateContent[i].blockType)
                      break
                  }
                }
              }
            }
          }

          isFetching.current = true

          fetchTemplateContent().finally(() => {
            isFetching.current = false
          })
        }
      }
    }
  }, [checkboxValue, templateValue])

  return <></>
}
