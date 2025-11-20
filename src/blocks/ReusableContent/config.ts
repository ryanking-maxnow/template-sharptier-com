import { Content } from '@/blocks/Content/config'
import { TemplatesBlocks } from '@/collections/Templates'
import type { Block } from 'payload'

export const ReusableContent: Block = {
  slug: 'reusableContent',
  interfaceName: 'ReusableContentBlock',
  fields: [
    {
      name: 'template',
      type: 'relationship',
      relationTo: 'templates',
      required: true,
    },
    {
      name: 'overrideContent',
      type: 'checkbox',
      admin: {
        condition: (data, siblingData) => {
          return !!siblingData.template
        },
      },
      hooks: {
        beforeChange: [
          async ({ data, siblingData, req, value }) => {
            if (value) {
              if (siblingData.template) {
                const templatesCollection = req.payload.collections.templates

                if (
                  templatesCollection &&
                  (!siblingData.content || siblingData.content.length === 0)
                ) {
                  const templateDoc = await req.payload.findByID({
                    id: siblingData.template,
                    collection: 'templates',
                    req,
                  })

                  if (templateDoc && 'content' in templateDoc) {
                    siblingData.content = templateDoc.content
                  }
                }
              }
            } else {
              if (siblingData) {
                siblingData.content = null
              }
            }
          },
        ],
      },
    },
    {
      name: 'content',
      type: 'blocks',
      admin: {
        condition: (data, siblingData) => {
          return Boolean(
            siblingData.overrideContent && siblingData.content && siblingData.content.length >= 0,
          )
        },
      },
      blocks: TemplatesBlocks,
    },
  ],
  labels: {
    plural: 'Reusable Content',
    singular: 'Reusable Content',
  },
}
