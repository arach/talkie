"use client"
import React, { useState, useCallback, useEffect } from 'react'
import Image from 'next/image'
import { ChevronLeft, ChevronRight, Smartphone, Tablet, X } from 'lucide-react'

const screenshots = [
  { src: '/screenshots/iphone-16-pro-max-1.png', alt: 'Talkie on iPhone' },
  { src: '/screenshots/iphone-16-pro-max-2.png', alt: 'Talkie on iPhone' },
  { src: '/screenshots/iphone-16-pro-max-3.png', alt: 'Talkie on iPhone' },
  { src: '/screenshots/iphone-16-pro-max-4.png', alt: 'Talkie on iPhone' },
  { src: '/screenshots/iphone-16-pro-max-5.png', alt: 'Talkie on iPhone' },
  { src: '/screenshots/iphone-16-pro-max-6.png', alt: 'Talkie on iPhone' },
  { src: '/screenshots/iphone-16-pro-max-7.png', alt: 'Talkie on iPhone' },
]

const ipadScreenshots = [
  { src: '/screenshots/ipad-air-13-1.png', alt: 'Talkie on iPad' },
  { src: '/screenshots/ipad-air-13-2.png', alt: 'Talkie on iPad' },
  { src: '/screenshots/ipad-air-13-3.png', alt: 'Talkie on iPad' },
  { src: '/screenshots/ipad-air-13-4.png', alt: 'Talkie on iPad' },
  { src: '/screenshots/ipad-air-13-5.png', alt: 'Talkie on iPad' },
]

export default function ScreenshotsSection() {
  const [currentIndex, setCurrentIndex] = useState(0)
  const [device, setDevice] = useState('iPhone')
  const [lightboxOpen, setLightboxOpen] = useState(false)

  const currentScreenshots = device === 'iPhone' ? screenshots : ipadScreenshots

  const nextSlide = useCallback(() => {
    setCurrentIndex((prev) => (prev + 1) % currentScreenshots.length)
  }, [currentScreenshots.length])

  const prevSlide = useCallback(() => {
    setCurrentIndex((prev) => (prev - 1 + currentScreenshots.length) % currentScreenshots.length)
  }, [currentScreenshots.length])

  const switchDevice = (newDevice) => {
    setDevice(newDevice)
    setCurrentIndex(0)
  }

  // Keyboard navigation for lightbox
  useEffect(() => {
    if (!lightboxOpen) return
    const handleKeyDown = (e) => {
      if (e.key === 'Escape') setLightboxOpen(false)
      if (e.key === 'ArrowRight') nextSlide()
      if (e.key === 'ArrowLeft') prevSlide()
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [lightboxOpen, nextSlide, prevSlide])

  // Prevent body scroll when lightbox is open
  useEffect(() => {
    if (lightboxOpen) {
      document.body.style.overflow = 'hidden'
    } else {
      document.body.style.overflow = ''
    }
    return () => { document.body.style.overflow = '' }
  }, [lightboxOpen])

  return (
    <>
      <div className="py-6">
        {/* Device Toggle */}
        <div className="flex items-center justify-center gap-2 mb-4">
          <button
            onClick={() => switchDevice('iPhone')}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-[10px] font-mono font-bold uppercase tracking-wider rounded transition-colors ${
              device === 'iPhone'
                ? 'bg-zinc-900 dark:bg-white text-white dark:text-black'
                : 'bg-zinc-200 dark:bg-zinc-700 text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300'
            }`}
          >
            <Smartphone className="w-3 h-3" />
            iPhone
          </button>
          <button
            onClick={() => switchDevice('iPad')}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-[10px] font-mono font-bold uppercase tracking-wider rounded transition-colors ${
              device === 'iPad'
                ? 'bg-zinc-900 dark:bg-white text-white dark:text-black'
                : 'bg-zinc-200 dark:bg-zinc-700 text-zinc-500 hover:text-zinc-700 dark:hover:text-zinc-300'
            }`}
          >
            <Tablet className="w-3 h-3" />
            iPad
          </button>
        </div>

        {/* Carousel */}
        <div className="relative">
          {/* Navigation Buttons */}
          <button
            onClick={prevSlide}
            className="absolute left-1 top-1/2 -translate-y-1/2 z-10 p-1.5 bg-white/90 dark:bg-zinc-800/90 rounded-full shadow hover:bg-white dark:hover:bg-zinc-700 transition-colors"
            aria-label="Previous screenshot"
          >
            <ChevronLeft className="w-4 h-4 text-zinc-700 dark:text-zinc-300" />
          </button>
          <button
            onClick={nextSlide}
            className="absolute right-1 top-1/2 -translate-y-1/2 z-10 p-1.5 bg-white/90 dark:bg-zinc-800/90 rounded-full shadow hover:bg-white dark:hover:bg-zinc-700 transition-colors"
            aria-label="Next screenshot"
          >
            <ChevronRight className="w-4 h-4 text-zinc-700 dark:text-zinc-300" />
          </button>

          {/* Screenshot Display */}
          <div
            className="flex items-center justify-center px-10 cursor-pointer group"
            onClick={() => setLightboxOpen(true)}
          >
            {device === 'iPhone' ? (
              <div className="w-56 transition-all duration-300 group-hover:scale-[1.02]">
                <div className="relative aspect-[9/19.5] rounded-[1.5rem] overflow-hidden shadow-xl border-2 border-zinc-800 bg-black">
                  <Image
                    src={currentScreenshots[currentIndex].src}
                    alt={currentScreenshots[currentIndex].alt}
                    fill
                    className="object-cover"
                    sizes="224px"
                  />
                </div>
                <p className="text-[10px] text-center text-zinc-500 mt-2 opacity-0 group-hover:opacity-100 transition-opacity">
                  Click to enlarge
                </p>
              </div>
            ) : (
              <div className="w-full max-w-sm transition-all duration-300 group-hover:scale-[1.02]">
                <div className="relative aspect-[4/3] rounded-xl overflow-hidden shadow-xl border-2 border-zinc-800 bg-black">
                  <Image
                    src={currentScreenshots[currentIndex].src}
                    alt={currentScreenshots[currentIndex].alt}
                    fill
                    className="object-cover"
                    sizes="384px"
                  />
                </div>
                <p className="text-[10px] text-center text-zinc-500 mt-2 opacity-0 group-hover:opacity-100 transition-opacity">
                  Click to enlarge
                </p>
              </div>
            )}
          </div>

          {/* Dots Indicator */}
          <div className="flex items-center justify-center gap-1.5 mt-3">
            {currentScreenshots.map((_, index) => (
              <button
                key={index}
                onClick={() => setCurrentIndex(index)}
                className={`w-1.5 h-1.5 rounded-full transition-all ${
                  index === currentIndex
                    ? 'bg-zinc-900 dark:bg-white w-3'
                    : 'bg-zinc-300 dark:bg-zinc-600 hover:bg-zinc-400 dark:hover:bg-zinc-500'
                }`}
                aria-label={`Go to screenshot ${index + 1}`}
              />
            ))}
          </div>
        </div>
      </div>

      {/* Lightbox */}
      {lightboxOpen && (
        <div
          className="fixed inset-0 z-50 bg-black/95 flex items-center justify-center p-4"
          onClick={() => setLightboxOpen(false)}
        >
          {/* Close button */}
          <button
            onClick={() => setLightboxOpen(false)}
            className="absolute top-4 right-4 p-2 text-white/70 hover:text-white transition-colors"
            aria-label="Close lightbox"
          >
            <X className="w-6 h-6" />
          </button>

          {/* Navigation */}
          <button
            onClick={(e) => { e.stopPropagation(); prevSlide() }}
            className="absolute left-4 top-1/2 -translate-y-1/2 p-3 bg-white/10 hover:bg-white/20 rounded-full transition-colors"
            aria-label="Previous screenshot"
          >
            <ChevronLeft className="w-6 h-6 text-white" />
          </button>
          <button
            onClick={(e) => { e.stopPropagation(); nextSlide() }}
            className="absolute right-4 top-1/2 -translate-y-1/2 p-3 bg-white/10 hover:bg-white/20 rounded-full transition-colors"
            aria-label="Next screenshot"
          >
            <ChevronRight className="w-6 h-6 text-white" />
          </button>

          {/* Large Screenshot */}
          <div
            className={`relative ${device === 'iPhone' ? 'h-[85vh] aspect-[9/19.5]' : 'w-[85vw] max-w-4xl aspect-[4/3]'}`}
            onClick={(e) => e.stopPropagation()}
          >
            <Image
              src={currentScreenshots[currentIndex].src}
              alt={currentScreenshots[currentIndex].alt}
              fill
              className="object-contain rounded-lg"
              sizes="85vw"
              priority
            />
          </div>

          {/* Counter */}
          <div className="absolute bottom-4 left-1/2 -translate-x-1/2 text-white/70 text-sm font-mono">
            {currentIndex + 1} / {currentScreenshots.length}
          </div>
        </div>
      )}
    </>
  )
}
