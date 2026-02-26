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
      name: 'useTemplateValues',
      type: 'checkbox',
      label: 'Use Template Values',
      defaultValue: true,
      admin: {
        condition: (data, siblingData) => {
          return !!siblingData.template
        },
      },
    },
    {
      name: 'content',
      type: 'blocks',
      admin: {
        condition: (data, siblingData) => {
          return Boolean(siblingData.content && siblingData.content.length > 0)
        },
      },
      blocks: TemplatesBlocks,
    },
    {
      // Custom UI to manage the content fetched from the selected template
      name: 'contentManager',
      type: 'ui',
      admin: {
        components: {
          Field: {
            path: '@/blocks/ReusableContent/ContentManager#ContentManager',
          },
        },
      },
    },
  ],
  labels: {
    plural: 'Reusable Content',
    singular: 'Reusable Content',
  },
}
