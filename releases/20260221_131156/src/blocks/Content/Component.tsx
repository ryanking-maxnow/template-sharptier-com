import { cn } from '@/utilities/ui'
import React from 'react'
import RichText from '@/components/RichText'

import type { ContentBlock as ContentBlockProps } from '@/payload-types'

export const ContentBlock: React.FC<ContentBlockProps> = (props) => {
  const { richText } = props

  return (
    <div className="container my-16">
      {richText && <RichText data={richText} enableGutter={false} />}
    </div>
  )
}
