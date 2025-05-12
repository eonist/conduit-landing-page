// GitHub Stars Counter
document.addEventListener('DOMContentLoaded', function() {
    // Default stars count from the design
    const defaultStarsCount = 134;
    
    // Configuration for GitHub API
    const repoOwner = 'eonist';
    const repoName = 'claude-talk-to-figma-mcp';
    
    // Element that displays the stars count
    const starsCountElement = document.getElementById('stars-count');
    
    /**
     * Fetch stars count from GitHub API and update the display
     */
    async function fetchStarsCount() {
        try {
            const response = await fetch(`https://api.github.com/repos/${repoOwner}/${repoName}`);
            
            if (!response.ok) {
                throw new Error('GitHub API request failed');
            }
            
            const data = await response.json();
            const starsCount = data.stargazers_count || defaultStarsCount;
            
            updateStarsCount(starsCount);
        } catch (error) {
            console.error('Error fetching GitHub stars:', error);
            // Use default count if API fails
            updateStarsCount(defaultStarsCount);
        }
    }
    
    /**
     * Update the stars count display
     * @param {number} count - Number of stars
     */
    function updateStarsCount(count) {
        starsCountElement.textContent = `${count} stars on GitHub`;
    }
    
    // Initialize the stars counter
    fetchStarsCount();
    
    // Add click event to the download button
    const downloadBtn = document.querySelector('.download-btn');
    if (downloadBtn) {
        downloadBtn.addEventListener('click', function() {
            // In a real implementation, this would link to the actual download URL
            window.open('https://github.com/' + repoOwner + '/' + repoName, '_blank');
        });
    }
});
