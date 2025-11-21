'use client'

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

  const checkboxPath = `${path.replace('contentManager', 'useTemplateValues')}`
  const templatePath = `${path.replace('contentManager', 'template')}`
  const contentPath = `${path.replace('contentManager', 'content')}`
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
      if (typeof contentValue !== 'undefined' && contentValue && checkboxValue) {
        // Cant remove the field entirely, so we loop through the rows and remove them
        for (let i = contentValue - 1; i >= 0; i--) {
          dispatchField({
            type: 'REMOVE_ROW',
            path: contentPath,
            rowIndex: i,
          })
        }
      }
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
            const templateDoc = await res.json()
            if (templateDoc && 'content' in templateDoc) {
              const templateContent = templateDoc.content

              if (
                contentSchemaPath &&
                templateDoc &&
                Array.isArray(templateContent) &&
                templateContent.length > 0
              ) {
                for (let i = 0; i < templateContent.length; i++) {
                  addFieldRow({
                    subFieldState: {
                      [`richText`]: {
                        value: templateContent[i].richText || null,
                      },
                    },
                    path: contentPath,
                    blockType: templateContent[i].blockType,
                    rowIndex: i,
                    schemaPath: contentSchemaPath,
                  })
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
