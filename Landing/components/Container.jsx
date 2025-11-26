import React from 'react'

export default function Container({ className = '', children }) {
  return (
    <div className={`mx-auto w-full max-w-[56rem] md:max-w-[60rem] lg:max-w-[64rem] xl:max-w-[72rem] 2xl:max-w-[80rem] px-6 ${className}`}>{children}</div>
  )
}
