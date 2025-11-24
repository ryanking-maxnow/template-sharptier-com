import type { Block, CollectionConfig } from 'payload'

import { anyone } from '../access/anyone'
import { authenticated } from '../access/authenticated'
import { Content } from '@/blocks/Content/config'

// We need to make sure our ReusableContent block can use the exact same blocks as our Templates collection
export const TemplatesBlocks: Block[] = [Content]

export const Templates: CollectionConfig = {
  slug: 'templates',
  access: {
    create: authenticated,
    delete: authenticated,
    read: anyone,
    update: authenticated,
  },
  admin: {
    useAsTitle: 'title',
  },
  fields: [
    {
      name: 'title',
      type: 'text',
      required: true,
    },
    {
      name: 'content',
      type: 'blocks',
      blocks: TemplatesBlocks,
    },
  ],
}
