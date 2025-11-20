import { cn } from '@/utilities/ui'
import React from 'react'
import RichText from '@/components/RichText'

import type { ReusableContentBlock as ReusableContentBlockProps } from '@/payload-types'

import { CMSLink } from '../../components/Link'
import { RenderBlocks } from '@/blocks/RenderBlocks'

export const ReusableContentBlock: React.FC<ReusableContentBlockProps> = (props) => {
  const { content, template, overrideContent } = props

  const contentToRender = overrideContent
    ? content
    : typeof template === 'object'
      ? template?.content
      : null

  return (
    <div className="container my-16">
      {contentToRender && contentToRender.length > 0 ? (
        <RenderBlocks blocks={contentToRender} />
      ) : (
        <></>
      )}
    </div>
  )
}
