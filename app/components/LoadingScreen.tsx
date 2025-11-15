interface LoadingScreenProps {
  message: string;
  percent: number;
}

export default function LoadingScreen({ message, percent }: LoadingScreenProps) {
  return (
    <div className="loading-overlay">
      <div className="loading-content">
        <div className="loading-logo batarang-spinner batarang-glow">
          <img
            src="/images/png-transparent-batman-superman-injustice-2-comics-batman-comics-heroes-logo-removebg-preview.png"
            alt="Batman Batarang"
          />
        </div>

        <div className="loading-message">{message}</div>

        <div className="loading-progress">
          <div className="progress-bar-container">
            <div
              className="progress-bar-fill"
              style={{ width: `${percent}%` }}
            ></div>
          </div>
          <div className="loading-percent">{percent}%</div>
        </div>
      </div>
    </div>
  );
}
