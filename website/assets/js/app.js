/**
 * Convro Website JavaScript
 * Alpine.js-based interactions
 */

// Main Alpine.js app
document.addEventListener('alpine:init', () => {
    // Global app state
    Alpine.store('app', {
        theme: localStorage.getItem('theme') || 'light',

        init() {
            this.applyTheme();
            this.setupThemeWatcher();
        },

        applyTheme() {
            document.documentElement.setAttribute('data-theme', this.theme);
            if (this.theme === 'dark') {
                document.documentElement.classList.add('dark');
            } else {
                document.documentElement.classList.remove('dark');
            }
        },

        setupThemeWatcher() {
            // Watch for system theme changes
            const mediaQuery = window.matchMedia('(prefers-color-scheme: dark)');
            mediaQuery.addEventListener('change', (e) => {
                if (!localStorage.getItem('theme')) {
                    this.theme = e.matches ? 'dark' : 'light';
                    this.applyTheme();
                }
            });
        }
    });
});

// Global app data
function app() {
    return {
        theme: localStorage.getItem('theme') || 'light',

        init() {
            this.applyTheme();

            // Remove no-transition class after initial load
            setTimeout(() => {
                document.body.classList.remove('no-transition');
            }, 100);
        },

        toggleTheme() {
            this.theme = this.theme === 'light' ? 'dark' : 'light';
            this.applyTheme();
            localStorage.setItem('theme', this.theme);

            // Dispatch custom event
            window.dispatchEvent(new CustomEvent('theme-changed', {
                detail: { theme: this.theme }
            }));
        },

        applyTheme() {
            document.documentElement.setAttribute('data-theme', this.theme);
            if (this.theme === 'dark') {
                document.documentElement.classList.add('dark');
            } else {
                document.documentElement.classList.remove('dark');
            }
        }
    };
}

// Smooth scroll to anchor
function smoothScrollTo(target) {
    const element = document.querySelector(target);
    if (element) {
        const offset = 80; // Header height
        const elementPosition = element.getBoundingClientRect().top;
        const offsetPosition = elementPosition + window.pageYOffset - offset;

        window.scrollTo({
            top: offsetPosition,
            behavior: 'smooth'
        });
    }
}

// Handle anchor links
document.addEventListener('DOMContentLoaded', () => {
    // Smooth scroll for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            const href = this.getAttribute('href');
            if (href !== '#') {
                e.preventDefault();
                smoothScrollTo(href);
            }
        });
    });

    // Scroll to hash on page load
    if (window.location.hash) {
        setTimeout(() => {
            smoothScrollTo(window.location.hash);
        }, 100);
    }
});

// Intersection Observer for animations
const observerOptions = {
    threshold: 0.1,
    rootMargin: '0px 0px -50px 0px'
};

const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
        if (entry.isIntersecting) {
            entry.target.classList.add('animate-fade-in-up');
            observer.unobserve(entry.target);
        }
    });
}, observerOptions);

// Observe elements with data-animate attribute
document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('[data-animate]').forEach(el => {
        observer.observe(el);
    });
});

// Copy to clipboard functionality
function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(() => {
            showNotification('Copied to clipboard!', 'success');
        }).catch(err => {
            console.error('Failed to copy:', err);
            showNotification('Failed to copy', 'error');
        });
    } else {
        // Fallback for older browsers
        const textarea = document.createElement('textarea');
        textarea.value = text;
        textarea.style.position = 'fixed';
        textarea.style.opacity = '0';
        document.body.appendChild(textarea);
        textarea.select();
        try {
            document.execCommand('copy');
            showNotification('Copied to clipboard!', 'success');
        } catch (err) {
            console.error('Failed to copy:', err);
            showNotification('Failed to copy', 'error');
        }
        document.body.removeChild(textarea);
    }
}

// Simple notification system
function showNotification(message, type = 'info') {
    const notification = document.createElement('div');
    notification.className = `fixed bottom-4 right-4 z-50 px-6 py-3 rounded-lg shadow-lg transform transition-all duration-300 ${
        type === 'success' ? 'bg-green-500 text-white' :
        type === 'error' ? 'bg-red-500 text-white' :
        'bg-blue-500 text-white'
    }`;
    notification.textContent = message;
    notification.style.transform = 'translateY(100px)';
    notification.style.opacity = '0';

    document.body.appendChild(notification);

    // Animate in
    setTimeout(() => {
        notification.style.transform = 'translateY(0)';
        notification.style.opacity = '1';
    }, 10);

    // Animate out and remove
    setTimeout(() => {
        notification.style.transform = 'translateY(100px)';
        notification.style.opacity = '0';
        setTimeout(() => {
            document.body.removeChild(notification);
        }, 300);
    }, 3000);
}

// Lazy load images
if ('IntersectionObserver' in window) {
    const imageObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const img = entry.target;
                if (img.dataset.src) {
                    img.src = img.dataset.src;
                    img.removeAttribute('data-src');
                }
                imageObserver.unobserve(img);
            }
        });
    });

    document.addEventListener('DOMContentLoaded', () => {
        document.querySelectorAll('img[data-src]').forEach(img => {
            imageObserver.observe(img);
        });
    });
}

// Prevent FOUC (Flash of Unstyled Content)
document.addEventListener('DOMContentLoaded', () => {
    document.body.style.opacity = '1';
});

// Analytics (placeholder)
function trackEvent(category, action, label) {
    // Placeholder for analytics
    console.log('Event:', category, action, label);

    // Implement your analytics here (Google Analytics, Plausible, etc.)
    // Example: gtag('event', action, { 'event_category': category, 'event_label': label });
}

// External link tracking
document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('a[href^="http"]').forEach(link => {
        link.addEventListener('click', (e) => {
            trackEvent('External Link', 'Click', link.href);
        });
    });
});
